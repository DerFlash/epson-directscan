import AppKit
import DirectScanCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let storage: ScanStorage
    let diagnostics: Diagnostics
    var settings: ScanSettings
    var controller: ScanCoordinator!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var quitting = false
    private var terminationReplyPending = false
    private var folderPanel: NSOpenPanel?
    private var statusPanel: NSPanel?
    private var statusText: NSTextField?
    private var countsText: NSTextField?
    private var folderText: NSTextField?
    private var connectButton: NSButton?
    private var folderButton: NSButton?
    private lazy var connections = ConnectionActions(
        hasConsent: { UserDefaults.standard.bool(forKey: "EpsonTakeoverAcknowledged") },
        requestConsent: { [weak self] in self?.requestTakeoverConsent() ?? false },
        rememberConsent: { UserDefaults.standard.set(true, forKey: "EpsonTakeoverAcknowledged") },
        connect: { [weak self] in self?.connectAfterConsent(recovery: false) },
        recover: { [weak self] in self?.connectAfterConsent(recovery: true) })
    private var sleepWasListening = false
    init(storage: ScanStorage) {
        self.storage = storage; diagnostics = Diagnostics(root: storage.root)
        settings = (try? storage.loadSettings()) ?? ScanSettings()
        super.init()
        controller = ScanCoordinator(storage: storage, diagnostics: diagnostics, settings: { [weak self] in self?.settings ?? ScanSettings() })
        controller.onChange = { [weak self] in
            guard let self else { return }
            self.refreshIcon()
            if self.terminationReplyPending && !self.controller.busy {
                self.terminationReplyPending = false
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu; menu.delegate = self; menu.autoenablesItems = false
        let mainMenu = NSMenu()
        let rootItem = NSMenuItem(); let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Epson DirectScan beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem); rootItem.submenu = appMenu; mainMenu.addItem(rootItem)
        NSApp.mainMenu = mainMenu
        statusItem.button?.setAccessibilityLabel("Epson DirectScan")
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
        else if !UserDefaults.standard.bool(forKey: "EpsonTakeoverAcknowledged") {
            DispatchQueue.main.async { [weak self] in self?.showStatus() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async { [weak self] in self?.showStatus() }
        return false
    }
    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = controller.policy.phase == .error ? "exclamationmark.triangle" : controller.policy.phase == .scanning ? "scanner.fill" : "scanner"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Epson DirectScan")
        image?.isTemplate = true; button.image = image
        button.toolTip = "Epson DirectScan – " + controller.message
        statusText?.stringValue = controller.message
        countsText?.stringValue = "Tastendrücke: \(controller.buttonEvents) · Gespeicherte JPGs: \(controller.imagesSaved)"
        folderText?.stringValue = "Ordner: " + (settings.destination.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "noch nicht gewählt")
        connectButton?.title = controller.listening ? "Pausieren und freigeben" : "Mit Epson verbinden"
        connectButton?.isEnabled = !controller.busy && folderPanel == nil
        folderButton?.isEnabled = !controller.busy && folderPanel == nil
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
        add("Status anzeigen …", #selector(showStatus))
        add("Tastendrücke: \(controller.buttonEvents) · JPGs: \(controller.imagesSaved)", enabled: false)
        menu.addItem(.separator())
        add(controller.listening ? "Pausieren und Scanner freigeben" : "Mit Epson verbinden", #selector(toggleListening), enabled: !controller.busy && folderPanel == nil)
        add("Ablageordner wählen …", #selector(chooseFolder), enabled: !controller.busy && folderPanel == nil)
        add("Ablageordner öffnen", #selector(openFolder), enabled: settings.destination != nil)
        if let path = settings.destination { add("Ordner: " + URL(fileURLWithPath: path).lastPathComponent, enabled: false) }
        menu.addItem(.separator())
        add("JPG · 300 dpi · einseitig", enabled: false)
        add("Automatischer Zuschnitt", #selector(toggleCorrection(_:)), enabled: !controller.busy && folderPanel == nil, checked: settings.crop, value: "crop")
        add("Schräglagenkorrektur", #selector(toggleCorrection(_:)), enabled: !controller.busy && folderPanel == nil, checked: settings.deskew, value: "deskew")
        add("Automatische Drehung", #selector(toggleCorrection(_:)), enabled: !controller.busy && folderPanel == nil, checked: settings.rotate, value: "rotate")
        menu.addItem(.separator())
        add("Letztes JPG anzeigen", #selector(showLastFile), enabled: controller.lastFile != nil)
        add("Zurückgehaltene Scans und Protokoll öffnen", #selector(openRecovery))
        add("Fehler zurücksetzen und neu verbinden …", #selector(recover), enabled: !controller.busy && folderPanel == nil && needsRecovery)
        add("Über diese App …", #selector(about))
        menu.addItem(.separator())
        add("Beenden", #selector(quit))
    }
    private func persist(_ next: ScanSettings) -> Bool {
        do { try storage.saveSettings(next); settings = next; return true }
        catch { showError(error.localizedDescription); return false }
    }
    private var needsRecovery: Bool {
        controller.policy.phase == .error || (try? storage.hasUnfinishedJobs()) == true
    }
    @objc func chooseFolder() {
        guard !controller.busy, folderPanel == nil else { return }
        let wasListening = controller.listening
        if wasListening { controller.pause() }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); folderPanel = panel
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.title = "Ablageordner für JPG-Scans wählen"; panel.prompt = "Ordner verwenden"
        if let path = settings.destination { panel.directoryURL = URL(fileURLWithPath: path) }
        refreshIcon()
        panel.begin { [weak self] response in
            guard let self, let panel = self.folderPanel else { return }
            self.folderPanel = nil
            if response == .OK, let url = panel.url {
                do {
                    _ = try self.storage.validateDestination(url.path)
                    var next = self.settings; next.destination = url.path
                    _ = self.persist(next)
                } catch { self.showError(error.localizedDescription) }
            }
            if wasListening { self.controller.start() }
            else { self.showStatus() }
            self.refreshIcon()
        }
    }
    private func requestTakeoverConsent() -> Bool {
        let alert = NSAlert(); alert.messageText = "Epson-Taste für DirectScan übernehmen?"
        alert.informativeText = "Während DirectScan verbunden ist, pausieren die beiden Epson-Tastenhelfer. Nach bestätigter Scanner-Freigabe beim Pausieren oder Beenden werden sie wieder gestartet. Andere Epson-Scanprogramme bitte vorher schließen. Die Tastensteuerung dieser Beta ist noch nicht abgenommen."
        alert.addButton(withTitle: "Direktmodus aktivieren"); alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
    private func connectAfterConsent(recovery: Bool) {
        var next = settings; next.paused = false
        guard persist(next) else { return }
        if recovery { controller.recover() } else { controller.start() }
    }
    @objc private func toggleListening() {
        guard !controller.busy, folderPanel == nil else { return }
        if controller.listening {
            var next = settings; next.paused = true
            if persist(next) { controller.pause() }
            return
        }
        guard settings.destination != nil else { chooseFolder(); return }
        connections.connect()
    }
    @objc private func toggleCorrection(_ sender: NSMenuItem) {
        guard !controller.busy, folderPanel == nil, let key = sender.representedObject as? String else { return }
        var next = settings
        switch key { case "crop": next.crop.toggle(); case "deskew": next.deskew.toggle(); case "rotate": next.rotate.toggle(); default: return }
        _ = persist(next); refreshIcon()
    }
    @objc private func openFolder() { if let path = settings.destination { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } }
    @objc private func showLastFile() { if let url = controller.lastFile { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc private func openRecovery() { NSWorkspace.shared.open(storage.root) }
    @objc private func recover() {
        guard !controller.busy, folderPanel == nil, needsRecovery else { return }
        let alert = NSAlert(); alert.messageText = "Unbestätigte Scans geprüft?"
        alert.informativeText = "Zurückgehaltene Dateien bleiben im Wiederherstellungsordner. Es wird kein alter Scan erneut ausgeführt. Erst der nächste neue Tastendruck darf scannen."
        alert.addButton(withTitle: "Geprüft – neu verbinden"); alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            connections.recover()
        }
    }
    @objc private func showStatus() {
        if let folderPanel { NSApp.activate(ignoringOtherApps: true); folderPanel.makeKeyAndOrderFront(nil); return }
        if statusPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Epson DirectScan – Status"; panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false; panel.center()
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 240)); panel.contentView = content
            let status = NSTextField(wrappingLabelWithString: controller.message)
            status.frame = NSRect(x: 18, y: 154, width: 444, height: 62)
            status.font = .systemFont(ofSize: 14, weight: .medium); status.isSelectable = true
            content.addSubview(status); statusText = status
            let counts = NSTextField(labelWithString: ""); counts.frame = NSRect(x: 18, y: 126, width: 444, height: 20)
            content.addSubview(counts); countsText = counts
            let folder = NSTextField(labelWithString: ""); folder.frame = NSRect(x: 18, y: 102, width: 444, height: 20)
            content.addSubview(folder); folderText = folder
            let connect = NSButton(title: "Mit Epson verbinden", target: self, action: #selector(toggleListening))
            connect.bezelStyle = .rounded; connect.frame = NSRect(x: 16, y: 52, width: 218, height: 32)
            content.addSubview(connect); connectButton = connect
            let choose = NSButton(title: "Ablageordner wählen …", target: self, action: #selector(chooseFolder))
            choose.bezelStyle = .rounded; choose.frame = NSRect(x: 244, y: 52, width: 220, height: 32)
            content.addSubview(choose); folderButton = choose
            let options = NSButton(title: "Einstellungen …", target: self, action: #selector(showSettings))
            options.bezelStyle = .rounded; options.frame = NSRect(x: 16, y: 8, width: 180, height: 32)
            content.addSubview(options)
            let close = NSButton(title: "Schließen", target: self, action: #selector(closeStatus))
            close.bezelStyle = .rounded; close.frame = NSRect(x: 362, y: 8, width: 102, height: 32)
            content.addSubview(close); statusPanel = panel
        }
        refreshIcon(); NSApp.activate(ignoringOtherApps: true); statusPanel?.makeKeyAndOrderFront(nil)
    }
    @objc private func closeStatus() { statusPanel?.close() }
    @objc private func showSettings() {
        guard let content = statusPanel?.contentView else { return }
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 18, y: 44), in: content)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
        quitting = true; controller.pause()
        if controller.busy {
            terminationReplyPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.terminationReplyPending else { return }
                self.terminationReplyPending = false
                if !self.controller.sessionReleased { self.diagnostics.record("quit_without_release_services_memo_retained") }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        if controller.sessionReleased { try? controller.mode.restore() }
    }
}
