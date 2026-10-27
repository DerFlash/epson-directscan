import Foundation
import Darwin
import DirectScanCore

struct HelperEvent: Codable {
    let event: String
    var value: Int? = nil
    var file: String? = nil
}
enum HelperRole: Equatable { case button, scan(ScanSettings) }
protocol NativeHelper: AnyObject {
    var onEvent: ((HelperEvent) -> Void)? { get set }
    var onExit: ((Int32) -> Void)? { get set }
    func start() throws
    func cancel()
    func forceStop()
}

// Pipe events and process exit are delivered in order on the main queue.
final class NativeProcess: NativeHelper {
    var onEvent: ((HelperEvent) -> Void)?
    var onExit: ((Int32) -> Void)?
    private let process = Process()
    private let output = Pipe()
    init(executable: URL, arguments: [String]) {
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
    }
    convenience init(role: HelperRole, root: URL) throws {
        switch role {
        case .button:
            self.init(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/EpsonButtonReceiver"),
                      arguments: ["--parent", String(getpid()), "--root", root.path])
        case .scan(let settings):
            guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
            let data = try JSONEncoder().encode(settings)
            self.init(executable: executable, arguments: ["--scan-worker", root.path, data.base64EncodedString(), String(getpid())])
        }
    }
    func start() throws {
        try process.run()
        let stream = output.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [self] in
            var buffer = Data(); var lines = 0; var invalid = false
            var bytes = [UInt8](repeating: 0, count: 4096)
            while true {
                    let count = bytes.withUnsafeMutableBytes { Darwin.read(stream.fileDescriptor, $0.baseAddress, $0.count) }
                    if count == 0 { break }
                    if count < 0 {
                        if errno == EINTR { continue }
                        DispatchQueue.main.async { [weak self] in self?.onEvent?(HelperEvent(event: "error", value: -902)) }
                        cancel(); break
                    }
                    if invalid { continue }
                    buffer.append(contentsOf: bytes.prefix(count))
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = buffer[..<newline]; buffer.removeSubrange(...newline); lines += 1
                        guard line.count <= 4096, lines <= 4096,
                              let event = try? JSONDecoder().decode(HelperEvent.self, from: line) else {
                            invalid = true; break
                        }
                        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
                    }
                    if buffer.count > 4096 { invalid = true }
                    if invalid {
                        DispatchQueue.main.async { [weak self] in self?.onEvent?(HelperEvent(event: "error", value: -900)) }
                        cancel()
                    }
            }
            if !buffer.isEmpty && !invalid {
                DispatchQueue.main.async { [weak self] in self?.onEvent?(HelperEvent(event: "error", value: -901)) }
            }
            try? stream.close()
            process.waitUntilExit()
            let status = process.terminationStatus
            DispatchQueue.main.async { [weak self] in self?.onExit?(status) }
        }
    }
    func cancel() { if process.isRunning { process.terminate() } }
    func forceStop() { if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) } }
}
