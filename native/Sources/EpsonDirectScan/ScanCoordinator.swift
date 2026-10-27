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
    private var feedingReady = false
    private var feedingEnded = false
    private var feedingTransfer = false
    private var idleSince: TimeInterval?
    private var finishReason: JobEndReason?
    private var pauseAfterCollection = false
    private(set) var collectionPages = 0
    private(set) var lastCollectionIncomplete = false
    var collecting: Bool { if case .feeding? = role { return policy.phase == .scanning && !stopping }; return false }
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
            "lastFile": lastFile?.lastPathComponent ?? "", "listening": desiredActive,
            "collecting": collecting, "collectionPages": collectionPages])
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
        } catch { fail(error.localizedDescription, code: "receiver_start_failed") }
    }
    private func launch(_ next: HelperRole) throws {
        let process = try makeHelper(next)
        helper = process; role = next; closed = false; closeReported = false; files = 0; complete = nil; empty = false
        feedingReady = false; feedingEnded = false; feedingTransfer = false; idleSince = nil; finishReason = nil; collectionPages = 0; pauseAfterCollection = false
        process.onEvent = { [weak self, weak process] event in
            guard let self, let process, self.helper === process else { return }
            self.receive(event)
        }
        process.onExit = { [weak self, weak process] status in
            guard let self, let process, self.helper === process else { return }
            self.exited(status)
        }
        deadline = now() + (next == .button ? 20 : 140)
        if case .feeding = next { deadline = now() + 25 }
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
        case (.feeding?, "ready"):
            guard !feedingReady else { fail("Doppelte Einzugsbereitschaft.", code: "feeding_duplicate_ready"); return }
            feedingReady = true; idleSince = now(); deadline = nil
            update("Sammlung aktiv – Karten nachlegen · 0 Seiten")
        case (.feeding?, "batchBegin"):
            guard feedingReady, !feedingEnded, !feedingTransfer, finishReason == nil else { fail("Unerwarteter Einzugsstart.", code: "feeding_batch_invalid"); return }
            feedingTransfer = true; idleSince = nil; deadline = now() + 130
            update("Sammlung – Karte wird gescannt · \(collectionPages) Seiten")
        case (.feeding?, "batchEnd"):
            guard feedingReady, !feedingEnded else { fail("Unerwarteter Einzugsabschluss.", code: "feeding_batch_invalid"); return }
            feedingTransfer = false
            if finishReason == nil { idleSince = now(); deadline = nil }
            update("Sammlung aktiv – Karten nachlegen · \(collectionPages) Seiten")
        case (.feeding(let job)?, "page"):
            guard feedingReady, !feedingEnded, event.value == collectionPages + 1,
                  let name = event.file, !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
                  name.hasSuffix(".jpg"), let sheet = event.sheet, let side = event.side, [0,1].contains(side) else {
                fail("Unerwartete Sammlungsseite. Die Bilder bleiben erhalten.", code: "feeding_page_invalid"); return
            }
            do {
                try storage.stage(source: job.directory.appendingPathComponent(name), job: job, sheet: sheet, side: side == 0 ? .front : .back)
                collectionPages += 1; files = collectionPages
                if feedingTransfer && finishReason == nil { deadline = now() + 130 }
                update("Sammlung – \(collectionPages) Seiten übernommen")
            } catch { fail(error.localizedDescription, code: "feeding_stage_failed") }
        case (.feeding?, "end"):
            guard feedingReady, !feedingEnded, event.value == 0 else { fail("Sammlungsabschluss nicht bestätigt.", code: "feeding_end_invalid"); return }
            feedingEnded = true; feedingTransfer = false; idleSince = nil
            if finishReason == nil { finishReason = .stop }
            deadline = now() + 15
            update("Sammlung wird abgeschlossen …")
        case (.button?, "ready"):
            guard policy.phase == .searching else { return }
            policy.sessionReady(); deadline = nil
            diagnostics.record("button_receiver_ready"); update("Bereit – Epson-Taste drücken" + (lastCollectionIncomplete ? " · Letzte Karte unvollständig; vorhandene Seiten im PDF" : ""))
        case (.button?, "button"):
            guard event.value == 1, policy.buttonPressed() else { return }
            buttonEvents += 1; frozenSettings = settings()
            diagnostics.record("scan_button", values: ["count": buttonEvents, "source": 4])
            deadline = now() + 8
            update("Epson-Taste erkannt – Scanner wird übergeben …")
        case (.scan(let snapshot)?, "file"):
            guard policy.phase == .scanning, let name = event.file,
                  !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
                  name.lowercased().hasSuffix(snapshot.outputFormat == .pdf ? ".pdf" : ".jpg"), event.value == files + 1,
                  let destination = snapshot.destination else {
                fail("Unerwartete Scandatei. Zurückgehaltene Dateien bitte prüfen.", code: "worker_file_invalid"); return
            }
            files += 1; imagesSaved += 1
            lastFile = URL(fileURLWithPath: destination, isDirectory: true).appendingPathComponent(name)
            diagnostics.record("output_published", values: ["file": files]); update("\(files) Datei(en) gespeichert – Scan läuft …")
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
                if snapshot.automaticFeeding { try launch(.feeding(storage.beginJob(settings: snapshot))) }
                else { try launch(.scan(snapshot)) }
            case .scan?:
                guard complete == files && files > 0 || empty && files == 0,
                      try !storage.hasUnfinishedJobs() else { throw ScanFailure.unfinishedPages }
                diagnostics.record("scan_completed", values: ["pages": files])
                policy.completed(); policy.disconnected(); frozenSettings = nil
                try launch(.button)
            case .feeding(let job)?:
                guard feedingReady, feedingEnded, let finishReason else { throw ScanFailure.unfinishedPages }
                if collectionPages == 0 { try storage.discardEmpty(job: job) }
                else {
                    try storage.complete(job: job, reason: finishReason)
                    lastCollectionIncomplete = try storage.manifest(job: job).hasIncompleteSheet
                    let outputs = try storage.export(job: job)
                    lastFile = outputs.last; imagesSaved += collectionPages
                    try storage.finish(job: job)
                }
                diagnostics.record("collection_completed", values: ["pages": collectionPages])
                policy.completed(); policy.disconnected(); frozenSettings = nil
                if pauseAfterCollection { desiredActive = false; policy.pause(); restoreServices() }
                else { try launch(.button) }
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
    func finishCollection(pauseAfter: Bool = false) {
        guard collecting, feedingReady, !feedingEnded, finishReason == nil else { return }
        finishReason = .stop; pauseAfterCollection = pauseAfter; idleSince = nil; deadline = now() + 20
        helper?.finish(); update("Sammlung wird beendet …")
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
        } catch { policy.failed(); update("Epson-Dienste bleiben pausiert. " + error.localizedDescription) }
    }
    func checkDeadline() {
        if collecting, feedingReady, !feedingEnded, finishReason == nil, !feedingTransfer,
           let idleSince, case .feeding(let job)? = role,
           job.settings.feedingTimeoutSeconds > 0, now() - idleSince >= Double(job.settings.feedingTimeoutSeconds) {
            finishReason = .idleTimeout; self.idleSince = nil; deadline = now() + 20
            helper?.finish(); update("Wartezeit abgelaufen – Sammlung wird beendet …")
            return
        }
        guard let deadline, now() >= deadline else { return }
        if stopping {
            self.deadline = nil; releaseFailed = true; desiredActive = false; resumeAfterClose = false; policy.failed()
            helper?.forceStop(); update("Scanner-Freigabe dauert zu lange. Bitte App beenden und erneut öffnen.")
        } else { fail("Der Scanner antwortet nicht rechtzeitig. Bitte Verbindung und Dateien prüfen.", code: "helper_timeout") }
    }
}
