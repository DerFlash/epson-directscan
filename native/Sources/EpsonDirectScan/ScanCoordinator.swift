import AppKit
import DirectScanCore

final class ScanCoordinator {
    let storage: ScanStorage
    let diagnostics: Diagnostics
    let mode: EpsonServices
    let settings: () -> ScanSettings
    private let makeHelper: (HelperRole) throws -> NativeHelper
    private let conflictingApps: () -> Bool
    private let now: () -> TimeInterval
    var onChange: (() -> Void)?
    private(set) var policy = ScanPolicy()
    private(set) var message = "Pausiert"
    private(set) var buttonEvents = 0
    private(set) var imagesSaved = 0
    private(set) var lastFile: URL?
    private var helper: NativeHelper?
    private var role: HelperRole?
    private var desiredActive = false
    private var stopping = false
    private var releaseFailed = false
    private var resumeAfterClose = false
    private var closed = false
    private var closeReported = false
    private var frozenSettings: ScanSettings?
    private var files = 0
    private var complete: Int?
    private var empty = false
    private var deadline: TimeInterval?
    private var timer: Timer?
    var busy: Bool { policy.phase == .scanning || stopping || releaseFailed }
    var listening: Bool { desiredActive }
    var sessionReleased: Bool { helper == nil && !releaseFailed }
    init(storage: ScanStorage, diagnostics: Diagnostics, settings: @escaping () -> ScanSettings,
         services: EpsonServices? = nil, makeHelper: ((HelperRole) throws -> NativeHelper)? = nil,
         conflictingApps: @escaping () -> Bool = {
             ["org.scansmart.autosave.beta", "com.epson.scan.Epson-ScanSmart", "com.epson.ProjectManager"].contains {
                 !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
             }
         }, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.storage = storage; self.diagnostics = diagnostics; self.settings = settings
        mode = services ?? EpsonButtonMode(root: storage.root, diagnostics: diagnostics)
        self.makeHelper = makeHelper ?? { try NativeProcess(role: $0, root: storage.root) }
        self.conflictingApps = conflictingApps; self.now = now
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkDeadline() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    deinit { timer?.invalidate() }
    private func update(_ text: String? = nil) {
        if let text { message = text }
        diagnostics.status(["phase": policy.phase.rawValue, "message": message,
            "buttonEvents": buttonEvents, "imagesSaved": imagesSaved,
            "lastFile": lastFile?.lastPathComponent ?? "", "listening": desiredActive])
        onChange?()
    }
    func start() {
        guard !desiredActive, !releaseFailed else { return }
        if stopping { resumeAfterClose = true; return }
        do {
            guard !settings().paused else { return }
            _ = try storage.validateDestination(settings().destination)
            guard try !storage.hasUnfinishedJobs() else { throw ScanFailure.unfinishedPages }
            guard !conflictingApps() else { update("Bitte ScanSmart, Event Manager und die alte AutoSave-App beenden."); return }
            try mode.acquire()
            desiredActive = true; policy.resume(); policy.recover()
            try launch(.button)
        } catch { fail("Tastenempfang konnte nicht starten. Bitte Treiber und Ordner prüfen.", code: "receiver_start_failed") }
    }
    private func launch(_ next: HelperRole) throws {
        let process = try makeHelper(next)
        helper = process; role = next; closed = false; closeReported = false; files = 0; complete = nil; empty = false
        process.onEvent = { [weak self, weak process] event in
            guard let self, let process, self.helper === process else { return }
            self.receive(event)
        }
        process.onExit = { [weak self, weak process] status in
            guard let self, let process, self.helper === process else { return }
            self.exited(status)
        }
        deadline = now() + (next == .button ? 20 : 140)
        update(next == .button ? "Verbinde Epson-Tastenempfänger …" : "Taste erkannt – Direktscan wird gestartet …")
        do { try process.start() }
        catch { helper = nil; role = nil; deadline = nil; throw error }
    }
    private func receive(_ event: HelperEvent) {
        guard !closeReported else {
            fail("Meldung nach abgeschlossener Scanner-Freigabe. Bitte neu verbinden.", code: "helper_late_event")
            return
        }
        if event.event == "closed" {
            closeReported = true
            closed = event.value == 0
            return
        }
        guard !stopping, desiredActive else { return }
        switch (role, event.event) {
        case (.button?, "ready"):
            guard policy.phase == .searching else { return }
            policy.sessionReady(); deadline = nil
            diagnostics.record("button_receiver_ready"); update("Bereit – Epson-Taste drücken")
        case (.button?, "button"):
            guard event.value == 1, policy.buttonPressed() else { return }
            buttonEvents += 1; frozenSettings = settings()
            diagnostics.record("scan_button", values: ["count": buttonEvents, "source": 4])
            deadline = now() + 8
            update("Epson-Taste erkannt – Scanner wird übergeben …")
        case (.scan(let snapshot)?, "file"):
            guard policy.phase == .scanning, let name = event.file,
                  !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
                  name.lowercased().hasSuffix(".jpg"), event.value == files + 1,
                  let destination = snapshot.destination else {
                fail("Unerwartete Scandatei. Zurückgehaltene Dateien bitte prüfen.", code: "worker_file_invalid"); return
            }
            files += 1; imagesSaved += 1
            lastFile = URL(fileURLWithPath: destination, isDirectory: true).appendingPathComponent(name)
            diagnostics.record("jpeg_published", values: ["page": files]); update("\(files) JPG gespeichert – Scan läuft …")
        case (.scan?, "complete"):
            guard complete == nil, let count = event.value, count > 0, count == files else {
                fail("Scanabschluss konnte nicht bestätigt werden.", code: "worker_complete_invalid"); return
            }
            complete = count
        case (.scan?, "empty"):
            guard files == 0, complete == nil else { fail("Unerwarteter Scanabschluss.", code: "worker_empty_invalid"); return }
            empty = true
        case (_, "error"):
            diagnostics.record("helper_error", values: ["code": event.value ?? 0])
            fail("Der Epson-Empfang oder Scan ist fehlgeschlagen. Bitte Treiber und zurückgehaltene Dateien prüfen.", code: "helper_failed")
        default:
            fail("Unerwartete Meldung des Scanner-Helfers.", code: "helper_protocol_failed")
        }
    }
    private func exited(_ status: Int32) {
        let previous = role
        helper = nil; role = nil; stopping = false; deadline = nil
        guard closed else {
            releaseFailed = true; desiredActive = false; resumeAfterClose = false; policy.failed()
            diagnostics.record("helper_release_unconfirmed", values: ["status": Int(status)])
            update("Scanner-Freigabe nicht bestätigt. Bitte App beenden und erneut öffnen.")
            return
        }
        if !desiredActive || policy.phase == .error || status != 0 {
            if desiredActive { desiredActive = false; policy.failed(); update("Scanner-Helfer beendet. Bitte Fehler prüfen und neu verbinden.") }
            restoreServices()
            return
        }
        do {
            switch previous {
            case .button?:
                guard policy.phase == .scanning, let snapshot = frozenSettings else { throw ScanFailure.invalidSettings }
                try snapshot.validate(); _ = try storage.validateDestination(snapshot.destination)
                try launch(.scan(snapshot))
            case .scan?:
                guard complete == files && files > 0 || empty && files == 0,
                      try !storage.hasUnfinishedJobs() else { throw ScanFailure.unfinishedPages }
                diagnostics.record("scan_completed", values: ["pages": files])
                policy.completed(); policy.disconnected(); frozenSettings = nil
                try launch(.button)
            case nil: throw ScanFailure.invalidSettings
            }
        } catch { fail(error.localizedDescription, code: "handoff_failed") }
    }
    func pause() {
        desiredActive = false; resumeAfterClose = false
        if releaseFailed { policy.failed(); update(); return }
        policy.pause()
        if let helper { stopping = true; deadline = now() + 6; helper.cancel(); update("Scanner wird freigegeben …") }
        else { restoreServices() }
    }
    func recover() {
        guard !busy else { return }
        pause()
        do { try storage.acknowledgeRecovery(); policy.recover(); start() }
        catch { fail(error.localizedDescription, code: "recovery_failed") }
    }
    private func fail(_ text: String, code: String) {
        desiredActive = false; resumeAfterClose = false; policy.failed()
        diagnostics.record(code); update(text)
        if let helper { stopping = true; deadline = now() + 6; helper.cancel() }
        else { restoreServices() }
    }
    private func restoreServices() {
        guard sessionReleased else { return }
        let resume = resumeAfterClose; resumeAfterClose = false
        do {
            try mode.restore()
            if policy.phase == .paused { update("Pausiert – Scanner für andere Programme freigegeben") }
            else { update() }
            if resume { DispatchQueue.main.async { [weak self] in self?.start() } }
        } catch { policy.failed(); update("Scanner frei, aber Epson-Dienste nicht wiederhergestellt. Bitte App erneut öffnen.") }
    }
    func checkDeadline() {
        guard let deadline, now() >= deadline else { return }
        if stopping {
            self.deadline = nil; releaseFailed = true; desiredActive = false; resumeAfterClose = false; policy.failed()
            helper?.forceStop(); update("Scanner-Freigabe dauert zu lange. Bitte App beenden und erneut öffnen.")
        } else { fail("Der Scanner antwortet nicht rechtzeitig. Bitte Verbindung und Dateien prüfen.", code: "helper_timeout") }
    }
}
