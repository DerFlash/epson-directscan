import AppKit
import DirectScanCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let storage: ScanStorage
    let diagnostics: Diagnostics
    var settings: ScanSettings
    var controller: ScannerController!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var quitting = false
    private var sleepWasListening = false
    init(storage: ScanStorage) {
        self.storage = storage; diagnostics = Diagnostics(root: storage.root)
        settings = (try? storage.loadSettings()) ?? ScanSettings()
        super.init()
        controller = ScannerController(storage: storage, diagnostics: diagnostics, settings: { [weak self] in self?.settings ?? ScanSettings() })
        controller.onChange = { [weak self] in self?.refreshIcon() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu; menu.delegate = self; menu.autoenablesItems = false
        refreshIcon()
        do { try controller.mode.restore() }
        catch { showError("Epson-Dienste konnten nicht wiederhergestellt werden: " + error.localizedDescription) }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.sleepWasListening = self.controller.listening; self.controller.pause()
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.sleepWasListening, !self.settings.paused else { return }
            self.sleepWasListening = false; self.controller.start()
        }
        do { _ = try storage.loadSettings() }
        catch { showError(error.localizedDescription); return }
        if settings.destination == nil {
            DispatchQueue.main.async { [weak self] in self?.chooseFolder() }
        } else if !settings.paused && UserDefaults.standard.bool(forKey: "EpsonTakeoverAcknowledged") { controller.start() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { statusItem?.button?.performClick(nil) }
        return false
    }
    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = controller.policy.phase == .error ? "exclamationmark.triangle" : controller.policy.phase == .scanning ? "scanner.fill" : "scanner"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Epson DirectScan")
        image?.isTemplate = true; button.image = image
        button.toolTip = "Epson DirectScan – " + controller.message
    }
    private func add(_ title: String, _ action: Selector? = nil, enabled: Bool = true, checked: Bool? = nil, value: String? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = enabled
        if let checked { item.state = checked ? .on : .off }
        item.representedObject = value; menu.addItem(item)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("Epson DirectScan Beta", enabled: false)
        add(controller.message, enabled: false)
        add("Tastendrücke: \(controller.buttonEvents) · JPGs: \(controller.imagesSaved)", enabled: false)
        menu.addItem(.separator())
        add(controller.listening ? "Pausieren und Scanner freigeben" : "Mit Epson verbinden", #selector(toggleListening), enabled: !controller.busy)
        add("Ablageordner wählen …", #selector(chooseFolder), enabled: !controller.busy)
        add("Ablageordner öffnen", #selector(openFolder), enabled: settings.destination != nil)
        if let path = settings.destination { add("Ordner: " + URL(fileURLWithPath: path).lastPathComponent, enabled: false) }
        menu.addItem(.separator())
        add("JPG · 300 dpi · einseitig", enabled: false)
        add("Automatischer Zuschnitt", #selector(toggleCorrection(_:)), enabled: !controller.busy, checked: settings.crop, value: "crop")
        add("Schräglagenkorrektur", #selector(toggleCorrection(_:)), enabled: !controller.busy, checked: settings.deskew, value: "deskew")
        add("Automatische Drehung", #selector(toggleCorrection(_:)), enabled: !controller.busy, checked: settings.rotate, value: "rotate")
        menu.addItem(.separator())
        add("Letztes JPG anzeigen", #selector(showLastFile), enabled: controller.lastFile != nil)
        add("Zurückgehaltene Scans und Protokoll öffnen", #selector(openRecovery))
        add("Fehler zurücksetzen und neu verbinden …", #selector(recover), enabled: !controller.busy)
        add("Über diese App …", #selector(about))
        menu.addItem(.separator())
        add("Beenden", #selector(quit))
    }
    private func persist(_ next: ScanSettings) -> Bool {
        do { try storage.saveSettings(next); settings = next; return true }
        catch { showError(error.localizedDescription); return false }
    }
    @objc func chooseFolder() {
        guard !controller.busy else { return }
        let wasListening = controller.listening
        if wasListening { controller.pause() }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.title = "Ablageordner für JPG-Scans wählen"; panel.prompt = "Ordner verwenden"
        if let path = settings.destination { panel.directoryURL = URL(fileURLWithPath: path) }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try storage.validateDestination(url.path)
                var next = settings; next.destination = url.path
                _ = persist(next)
            } catch { showError(error.localizedDescription) }
        }
        if wasListening { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.controller.start() } }
        refreshIcon()
    }
    @objc private func toggleListening() {
        guard !controller.busy else { return }
        var next = settings
        if controller.listening { next.paused = true; if persist(next) { controller.pause() }; return }
        guard settings.destination != nil else { chooseFolder(); return }
        if !UserDefaults.standard.bool(forKey: "EpsonTakeoverAcknowledged") {
            let alert = NSAlert(); alert.messageText = "Epson-Taste für DirectScan übernehmen?"
            alert.informativeText = "Während DirectScan verbunden ist, pausieren die beiden Epson-Tastenhelfer. Beim Pausieren oder Beenden werden sie wieder gestartet. Andere Epson-Scanprogramme bitte vorher schließen. Die Tastensteuerung dieser Beta ist noch nicht abgenommen."
            alert.addButton(withTitle: "Direktmodus aktivieren"); alert.addButton(withTitle: "Abbrechen")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            UserDefaults.standard.set(true, forKey: "EpsonTakeoverAcknowledged")
        }
        next.paused = false
        if persist(next) { controller.start() }
    }
    @objc private func toggleCorrection(_ sender: NSMenuItem) {
        guard !controller.busy, let key = sender.representedObject as? String else { return }
        var next = settings
        switch key { case "crop": next.crop.toggle(); case "deskew": next.deskew.toggle(); case "rotate": next.rotate.toggle(); default: return }
        _ = persist(next)
    }
    @objc private func openFolder() { if let path = settings.destination { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } }
    @objc private func showLastFile() { if let url = controller.lastFile { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc private func openRecovery() { NSWorkspace.shared.open(storage.root) }
    @objc private func recover() {
        guard !controller.busy else { return }
        let alert = NSAlert(); alert.messageText = "Unbestätigte Scans geprüft?"
        alert.informativeText = "Zurückgehaltene Dateien bleiben im Wiederherstellungsordner. Es wird kein alter Scan erneut ausgeführt. Erst der nächste neue Tastendruck darf scannen."
        alert.addButton(withTitle: "Geprüft – neu verbinden"); alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            var next = settings; next.paused = false
            if persist(next) { controller.recover() }
        }
    }
    @objc private func about() {
        let alert = NSAlert(); alert.messageText = "Epson DirectScan 0.2 Beta"
        alert.informativeText = "Unabhängige Mac-App für ES-C320W über USB. JPG, 300 dpi und die drei Bildkorrekturen verwenden den installierten Epson-Treiber. Keine Bedienungshilfen, kein Upload. Gerätetaste noch in Erprobung. Zum Start bei Anmeldung kannst du die App nach erfolgreichem Test in den macOS-Anmeldeobjekten hinzufügen."
        alert.addButton(withTitle: "OK"); NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    private func showError(_ text: String) {
        diagnostics.record("settings_error")
        let alert = NSAlert(); alert.messageText = "DirectScan benötigt deine Aufmerksamkeit"; alert.informativeText = text
        alert.addButton(withTitle: "OK"); NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateNow }
        quitting = true
        let wasBusy = controller.busy; controller.pause()
        if wasBusy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { NSApp.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { try? controller.mode.restore() }
}
