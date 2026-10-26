import AppKit
import ImageCaptureCore
import DirectScanCore

final class ScannerController: NSObject, ICDeviceBrowserDelegate, ICScannerDeviceDelegate {
    let storage: ScanStorage
    let diagnostics: Diagnostics
    let mode: EpsonButtonMode
    var settings: () -> ScanSettings
    var onChange: (() -> Void)?
    private(set) var policy = ScanPolicy()
    private(set) var message = "Pausiert"
    private(set) var buttonEvents = 0
    private(set) var imagesSaved = 0
    private(set) var lastFile: URL?
    private var browser: ICDeviceBrowser?
    private var scanner: ICScannerDevice?
    private var job: ScanJob?
    private var pages = 0
    private var selectedReady = false
    private var closing = false
    private var opening = false
    private var desiredActive = false
    private var resumeAfterClose = false
    private var observingButton = false
    private var buttonSource: String?
    private var deadline: Date?
    private var timer: Timer?
    var busy: Bool { policy.phase == .scanning || closing }
    var listening: Bool { desiredActive }
    init(storage: ScanStorage, diagnostics: Diagnostics, settings: @escaping () -> ScanSettings) {
        self.storage = storage; self.diagnostics = diagnostics; self.settings = settings
        mode = EpsonButtonMode(root: storage.root, diagnostics: diagnostics)
        super.init()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkDeadline() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func update(_ text: String? = nil) {
        if let text { message = text }
        diagnostics.status(["phase": policy.phase.rawValue, "message": message,
            "buttonEvents": buttonEvents, "imagesSaved": imagesSaved,
            "lastFile": lastFile?.lastPathComponent ?? "", "listening": desiredActive])
        onChange?()
    }
    func start() {
        guard !desiredActive else { return }
        if closing { resumeAfterClose = true; return }
        do {
            guard !settings().paused else { return }
            _ = try storage.validateDestination(settings().destination)
            guard try !storage.hasUnfinishedJobs() else { throw ScanFailure.unfinishedPages }
            let incompatible = ["org.scansmart.autosave.beta", "com.epson.scan.Epson-ScanSmart", "com.epson.ProjectManager"]
            guard !incompatible.contains(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) else {
                update("Bitte ScanSmart, Event Manager und die alte AutoSave-App beenden.")
                return
            }
            try mode.acquire()
            desiredActive = true; policy.resume(); policy.recover()
            let b = ICDeviceBrowser(); browser = b; b.delegate = self
            b.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.scanner.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
            b.start()
            update("Suche Epson ES-C320W über USB …")
        } catch { fail(error.localizedDescription, code: "start_failed", error: error) }
    }
    func pause() {
        desiredActive = false; resumeAfterClose = false; deadline = nil; selectedReady = false
        if job != nil { diagnostics.record("scan_interrupted_files_retained"); scanner?.cancelScan() }
        policy.pause()
        closeSession()
        do { try mode.restore() } catch { update("Epson-Dienste konnten nicht wiederhergestellt werden. Bitte App erneut öffnen."); return }
        update("Pausiert – Scanner für andere Programme freigegeben")
    }
    func recover() {
        guard !busy else { return }
        pause()
        do { try storage.acknowledgeRecovery(); job = nil; policy.recover(); start() }
        catch { fail(error.localizedDescription, code: "recovery_failed", error: error) }
    }
    private func closeSession() {
        guard let s = scanner else { finishClose(); return }
        if observingButton { s.removeObserver(self, forKeyPath: "buttonPressed"); observingButton = false }
        if opening { closing = true; deadline = Date(timeIntervalSinceNow: 20); return }
        if s.hasOpenSession {
            guard !closing else { return }
            closing = true; deadline = Date(timeIntervalSinceNow: 5); s.requestCloseSession()
        } else { finishClose() }
    }
    private func finishClose() {
        scanner?.delegate = nil; scanner = nil; selectedReady = false; closing = false; opening = false; deadline = nil
        browser?.stop(); browser?.delegate = nil; browser = nil; job = nil
        if resumeAfterClose { resumeAfterClose = false; DispatchQueue.main.async { [weak self] in self?.start() } }
    }
    private func fail(_ text: String, code: String, error: Error? = nil) {
        policy.failed(); desiredActive = false; resumeAfterClose = false; deadline = nil
        diagnostics.record(code, values: ["error": (error as NSError?)?.code ?? 0, "exported": pages])
        if job != nil { scanner?.cancelScan() }
        closeSession()
        do { try mode.restore() } catch { diagnostics.record("service_restore_failed") }
        update(text + (job == nil ? "" : " Zurückgehaltene Scans bleiben erhalten."))
    }
    private func checkDeadline() {
        guard let deadline, Date() >= deadline else { return }
        self.deadline = nil
        if closing { update("Scanner-Freigabe nicht bestätigt. Bitte die App beenden und erneut öffnen."); return }
        fail("Der Scanner antwortet nicht rechtzeitig. Bitte Scanner und Dateien prüfen.", code: "scanner_timeout")
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard !moreComing else { return }
        selectDevice()
    }
    func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) { selectDevice() }
    private func selectDevice() {
        guard desiredActive, scanner == nil, policy.phase == .searching else { return }
        let candidates = (browser?.devices ?? []).compactMap { $0 as? ICScannerDevice }.filter {
            $0.transportType == "ICTransportTypeUSB" && ($0.name?.contains("ES-C320W") ?? false)
        }
        guard candidates.count <= 1 else { fail("Mehrere passende USB-Scanner gefunden. Bitte nur einen verbinden.", code: "ambiguous_scanner"); return }
        guard let s = candidates.first else { return }
        scanner = s; opening = true; s.delegate = self; deadline = Date(timeIntervalSinceNow: 20)
        diagnostics.record("session_requested"); update("Verbinde Epson über USB …"); s.requestOpenSession()
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard device === scanner else { return }
        removed()
    }
    func didRemove(_ device: ICDevice) { if device === scanner { removed() } }
    private func removed() {
        let interrupted = job != nil
        if observingButton, let s = scanner { s.removeObserver(self, forKeyPath: "buttonPressed"); observingButton = false }
        scanner?.delegate = nil; scanner = nil; selectedReady = false; closing = false; deadline = nil; job = nil
        policy.disconnected()
        diagnostics.record(interrupted ? "device_removed_during_scan" : "device_removed")
        if interrupted {
            desiredActive = false; try? mode.restore()
            update("Scanner getrennt. Zurückgehaltene Scans bitte prüfen und Fehler zurücksetzen.")
        } else { update("Scanner getrennt – warte auf USB-Verbindung") }
    }
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        guard device === scanner else { return }
        opening = false
        if closing || !desiredActive {
            if error == nil { closing = true; deadline = Date(timeIntervalSinceNow: 5); device.requestCloseSession() }
            else { finishClose(); update() }
            return
        }
        if let error { fail("Scanner belegt oder nicht verfügbar. Bitte andere Scanprogramme schließen.", code: "session_open_failed", error: error) }
    }
    func deviceDidBecomeReady(_ device: ICDevice) {
        guard device === scanner, desiredActive, !closing, !selectedReady, let s = scanner else { return }
        s.requestSelect(.documentFeeder)
    }
    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: Error?) {
        guard scanner === self.scanner, desiredActive, !closing, !selectedReady else { return }
        if let error { fail("Der Papiereinzug konnte nicht gewählt werden.", code: "feeder_failed", error: error); return }
        guard functionalUnit is ICScannerFunctionalUnitDocumentFeeder else { fail("Der erwartete Papiereinzug fehlt.", code: "feeder_missing"); return }
        if scanner.responds(to: NSSelectorFromString("buttonPressed")) {
            scanner.addObserver(self, forKeyPath: "buttonPressed", options: [.new], context: nil)
            observingButton = true
        }
        selectedReady = true; deadline = nil; policy.sessionReady()
        diagnostics.record("ready", values: ["buttonObservation": observingButton ? 1 : 0])
        update(buttonEvents == 0 ? "Verbunden – Tastenempfang noch ungeprüft" : "Bereit – Epson-Taste drücken")
    }
    @objc(device:didReceiveButtonPress:)
    func deviceButton(_ device: ICDevice, button: String) { if device === scanner { buttonReceived(button, source: "delegate") } }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "buttonPressed", let device = object as? ICDevice else { super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context); return }
        let button = change?[.newKey] as? String
        DispatchQueue.main.async { [weak self] in
            guard let self, device === self.scanner, let button else { return }
            self.buttonReceived(button, source: "property")
        }
    }
    func device(_ device: ICDevice, didReceiveStatusInformation status: [ICDeviceStatus: Any]) {
        guard device === scanner, let value = status[.statusNotificationKey] as? String else { return }
        if value == ICButtonTypeScan { buttonReceived(value, source: "status") }
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, requestsSelect device: ICDevice) {
        if device === scanner { diagnostics.record("untyped_device_selection_ignored") }
    }
    private func buttonReceived(_ value: String, source: String) {
        guard value == ICButtonTypeScan else { diagnostics.record("other_button_ignored"); return }
        if let buttonSource, buttonSource != source { return }
        buttonSource = source; buttonEvents += 1
        diagnostics.record("scan_button", values: ["count": buttonEvents, "source": source == "delegate" ? 1 : source == "property" ? 2 : 3])
        guard desiredActive, selectedReady, !closing, let s = scanner,
              let feeder = s.selectedFunctionalUnit as? ICScannerFunctionalUnitDocumentFeeder,
              policy.phase == .ready else { update(); return }
        guard feeder.documentLoaded else { update("Taste erkannt – bitte eine Karte einlegen und erneut drücken"); return }
        guard policy.buttonPressed() else { return }
        do {
            let snapshot = settings()
            try configure(feeder, settings: snapshot)
            let next = try storage.beginJob(settings: snapshot); job = next; pages = 0
            s.transferMode = .fileBased; s.downloadsDirectory = next.directory
            s.documentName = "scan"; s.documentUTI = "public.jpeg"
            deadline = Date(timeIntervalSinceNow: 120)
            diagnostics.record("scan_started"); update("Karte wird gescannt …"); s.requestScan()
        } catch { fail(error.localizedDescription, code: "scan_setup_failed", error: error) }
    }
    private func configure(_ feeder: ICScannerFunctionalUnitDocumentFeeder, settings: ScanSettings) throws {
        guard feeder.supportedResolutions.contains(300) else { throw DriverConfigurationFailure.unavailable }
        feeder.resolution = 300; feeder.pixelDataType = .RGB
        guard let depth = ICScannerBitDepth(rawValue: 8), feeder.supportedBitDepths.contains(8) else { throw DriverConfigurationFailure.unavailable }
        feeder.bitDepth = depth; feeder.duplexScanningEnabled = false
        let size = feeder.documentSize; feeder.scanArea = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let features = feeder.vendorFeatures ?? []; var actual: [String: Int] = [:]
        if let f = features.first(where: { $0.internalName == "VF_AUTOCROP" }) as? ICScannerFeatureEnumeration {
            let requested = settings.crop ? 1 : 0
            guard let option = f.values.first(where: { $0.intValue == requested }) else { throw DriverConfigurationFailure.unavailable }
            f.currentValue = option
            guard let value = f.currentValue as? NSNumber else { throw DriverConfigurationFailure.rejected }
            actual["VF_AUTOCROP"] = value.intValue
        }
        for (key, requested) in [("VF_DESKEW", settings.deskew), ("VF_AUTOROTATE", settings.rotate)] {
            if let f = features.first(where: { $0.internalName == key }) as? ICScannerFeatureBoolean {
                f.value = requested; actual[key] = f.value ? 1 : 0
            }
        }
        try validateDriverCorrections(settings: settings, actual: actual)
        guard feeder.resolution == 300, feeder.pixelDataType == .RGB, !feeder.duplexScanningEnabled else { throw DriverConfigurationFailure.rejected }
    }
    func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        guard scanner === self.scanner, let job, policy.phase == .scanning else { return }
        do {
            let target = try storage.publish(source: url, job: job, page: pages + 1)
            pages += 1; imagesSaved += 1; lastFile = target
            diagnostics.record("jpeg_published", values: ["page": pages]); update("\(pages) JPG gespeichert – Scan läuft …")
        } catch { fail(error.localizedDescription, code: "publish_failed", error: error) }
    }
    func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: Error?) {
        guard scanner === self.scanner, policy.phase == .scanning, let job else { return }
        if let error { fail("Scan abgebrochen oder fehlgeschlagen. Bitte Scanner und zurückgehaltene Dateien prüfen.", code: "scan_failed", error: error); return }
        do {
            try storage.finish(job: job); self.job = nil; deadline = nil; policy.completed()
            diagnostics.record("scan_completed", values: ["pages": pages]); update("Bereit – \(pages) JPG gespeichert")
        } catch { fail(error.localizedDescription, code: "completion_unconfirmed", error: error) }
    }
    func device(_ device: ICDevice, didEncounterError error: Error?) {
        guard device === scanner, let error, !closing else { return }
        fail("Der Scanner meldet einen Fehler. Bitte Scanner und Dateien prüfen.", code: "device_error", error: error)
    }
    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        guard device === scanner else { return }
        let expected = closing; finishClose()
        if !expected { policy.failed(); desiredActive = false; try? mode.restore(); update("Scanner-Verbindung unerwartet beendet. Bitte neu verbinden.") }
        else { update() }
    }
}
