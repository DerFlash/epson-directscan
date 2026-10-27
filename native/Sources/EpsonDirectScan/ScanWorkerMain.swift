import AppKit
import Darwin
import DirectScanCore

private final class WorkerServices: EpsonServices {
    // The parent owns the service lease for the whole button/scan cycle.
    func acquire() throws {}
    func restore() throws {}
}

enum ScanWorkerMain {
    private static func emit(_ event: HelperEvent) {
        if let data = try? JSONEncoder().encode(event) {
            try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
        }
    }
    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count == 5, arguments[2].hasPrefix("/"),
              let data = Data(base64Encoded: arguments[3]),
              let settings = try? JSONDecoder().decode(ScanSettings.self, from: data),
              (try? settings.validate()) != nil, !settings.paused,
              let parent = Int32(arguments[4]), parent == getppid() else { return 2 }
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        var cancelled = false
        signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        termination.setEventHandler { cancelled = true }; interrupt.setEventHandler { cancelled = true }
        termination.resume(); interrupt.resume()
        defer { termination.cancel(); interrupt.cancel() }
        do {
            let storage = try ScanStorage(root: URL(fileURLWithPath: arguments[2], isDirectory: true))
            let lease = try ScannerLease(root: storage.root)
            defer { withExtendedLifetime(lease) {} }
            guard getppid() == parent else {
                emit(HelperEvent(event: "closed", value: 0)); return 1
            }
            let logs = storage.root.appendingPathComponent("WorkerLogs", isDirectory: true)
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let controller = ScannerController(storage: storage, diagnostics: Diagnostics(root: logs),
                settings: { settings }, services: WorkerServices(), conflictingApps: { false })
            var outcome: Int?
            var sentFiles = 0
            var requested = false
            var stopping = false
            var failed = false
            var closeDeadline: TimeInterval?
            let deadline = ProcessInfo.processInfo.systemUptime + 130
            controller.onChange = {
                if controller.imagesSaved > sentFiles, let file = controller.lastFile {
                    sentFiles = controller.imagesSaved
                    emit(HelperEvent(event: "file", value: sentFiles, file: file.lastPathComponent))
                }
            }
            controller.onScanFinished = { pages in
                outcome = pages; stopping = true
                closeDeadline = ProcessInfo.processInfo.systemUptime + 6
                controller.pause()
            }
            controller.start()
            while true {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                let now = ProcessInfo.processInfo.systemUptime
                if getppid() != parent || now >= deadline { cancelled = true }
                if cancelled && !stopping {
                    failed = true; stopping = true; closeDeadline = now + 6
                    controller.pause()
                }
                if controller.policy.phase == .error && !failed {
                    failed = true; stopping = true; closeDeadline = now + 6
                }
                if controller.policy.phase == .ready && !requested && !stopping {
                    requested = true; controller.scanAuthorized()
                }
                if stopping && controller.sessionReleased {
                    if failed { emit(HelperEvent(event: "error", value: controller.scannerReportedError ? -206 : -201)) }
                    else if let pages = outcome, pages > 0 { emit(HelperEvent(event: "complete", value: pages)) }
                    else if outcome == 0 { emit(HelperEvent(event: "empty", value: controller.emptyResult?.rawValue ?? 0)) }
                    else { emit(HelperEvent(event: "error", value: -202)); failed = true }
                    emit(HelperEvent(event: "closed", value: 0))
                    return failed ? 1 : 0
                }
                if let closeDeadline, now >= closeDeadline {
                    emit(HelperEvent(event: "error", value: -203))
                    return 1
                }
            }
        } catch {
            emit(HelperEvent(event: "error", value: -204))
            emit(HelperEvent(event: "closed", value: 0))
            return 1
        }
    }
}
