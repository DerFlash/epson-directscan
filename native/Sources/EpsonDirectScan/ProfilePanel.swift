import AppKit
import DirectScanCore
import UniformTypeIdentifiers

private final class ProfileFormView: NSView {
    override var isFlipped: Bool { true }
}

final class ProfilePanel: NSWindowController, NSWindowDelegate {
    private var snapshot: ScanSettings
    private var current: ScanProfile
    private var editingLegacy = false
    private var completed = false
    private let completion: (ScanSettings?) -> Bool
    private let profiles = NSPopUpButton(), area = NSPopUpButton(), orientation = NSPopUpButton()
    private let front = NSPopUpButton(), back = NSPopUpButton(), offset = NSPopUpButton()
    private let name = NSTextField(), width = NSTextField(), height = NSTextField(), destination = NSTextField()
    private let output = NSPopUpButton(), timeout = NSPopUpButton()
    private let duplex = NSButton(checkboxWithTitle: "Doppelseitig scannen", target: nil, action: nil)
    private let feeding = NSButton(checkboxWithTitle: "Kontinuierlicher Scan (Sammlungs-PDF)", target: nil, action: nil)
    private let crop = NSButton(checkboxWithTitle: "Automatischer Zuschnitt", target: nil, action: nil)
    private let deskew = NSButton(checkboxWithTitle: "Schräglagenkorrektur", target: nil, action: nil)
    private var profileSettings: ProfileScanSettings
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let removeButton = NSButton()
    private let transparent = NSButton(checkboxWithTitle: "Transparente Hülle vollständig erfassen", target: nil, action: nil)
    private let referenceButton = NSButton(), clearReferenceButton = NSButton()
    private let referenceStatus = NSTextField(wrappingLabelWithString: "")

    init(settings: ScanSettings, completion: @escaping (ScanSettings?) -> Bool) {
        var saved = settings; saved.rememberActiveProfileSettings()
        snapshot = saved; self.completion = completion
        profileSettings = ProfileScanSettings(settings: saved)
        current = saved.activeProfile ?? ScanProfile(name: "Bisherige Einstellungen")
        let panelHeight = min(884, max(240, (NSScreen.main?.visibleFrame.height ?? 964) - 80))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: panelHeight),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Scanprofile"; panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false; panel.delegate = self
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: panelHeight)); panel.contentView = root
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 64, width: 620, height: panelHeight - 64))
        scroll.identifier = NSUserInterfaceItemIdentifier("profile.scroll")
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let content = ProfileFormView(frame: NSRect(x: 0, y: 0, width: 620, height: 1100))
        scroll.documentView = content; root.addSubview(scroll)
        var y: CGFloat = 20
        func row(_ title: String, _ control: NSView, _ identifier: String) {
            let label = NSTextField(wrappingLabelWithString: title)
            label.frame = NSRect(x: 20, y: y + 3, width: 190, height: 32); content.addSubview(label)
            control.identifier = NSUserInterfaceItemIdentifier("profile." + identifier)
            control.frame = NSRect(x: 220, y: y, width: 375, height: 28); content.addSubview(control)
            y += 40
        }
        func section(_ title: String) {
            let label = NSTextField(labelWithString: title); label.font = .boldSystemFont(ofSize: 13)
            label.frame = NSRect(x: 20, y: y + 4, width: 575, height: 24); content.addSubview(label); y += 36
        }
        func profileChoice(_ title: String, value: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = value; profiles.menu?.addItem(item)
        }
        let templates = [("Neues Kartenprofil", "card"), ("Neuer Toploader", "holder"), ("Neues Belegprofil", "receipts")]
        let reservedNames = Set(["Bisherige Einstellungen"] + templates.map { $0.0 })
        let nameCounts = Dictionary(grouping: saved.profiles, by: \.name).mapValues(\.count)
        var nameOccurrences: [String: Int] = [:]
        profileChoice("Bisherige Einstellungen", value: "legacy")
        for profile in saved.profiles {
            nameOccurrences[profile.name, default: 0] += 1
            var title = profile.name
            if nameCounts[profile.name, default: 0] > 1 { title += " · Profil \(nameOccurrences[profile.name]!)" }
            else if reservedNames.contains(profile.name) { title += " · gespeichertes Profil" }
            profileChoice(title, value: profile.id.uuidString)
        }
        for (title, value) in templates { profileChoice(title, value: value) }
        profiles.autoenablesItems = false; profiles.menu?.autoenablesItems = false
        profiles.target = self; profiles.action = #selector(selectProfile)
        row("Profil bearbeiten", profiles, "selection"); row("Name", name, "name")
        let capability = NSTextField(labelWithString: "300 dpi · Farbe (durch Scanner vorgegeben)")
        capability.textColor = .secondaryLabelColor; capability.identifier = NSUserInterfaceItemIdentifier("profile.capability")
        capability.frame = NSRect(x: 20, y: y, width: 575, height: 24); content.addSubview(capability); y += 36

        section("Ausgabe und Einzug")
        row("Ablageordner", destination, "destination")
        destination.placeholderString = "Noch kein Ablageordner gewählt"; destination.frame.size.width = 242
        let folder = NSButton(title: "Ordner wählen …", target: self, action: #selector(chooseDestination))
        folder.identifier = NSUserInterfaceItemIdentifier("profile.chooseDestination"); folder.bezelStyle = .rounded
        folder.frame = NSRect(x: 472, y: y - 42, width: 126, height: 32); content.addSubview(folder)
        for (title, value) in [("JPG – jede Seite einzeln", "jpg"), ("PDF – eine Datei pro Blatt", "pdf"), ("Sammlungs-PDF – kontinuierlicher Scan", "collection")] {
            output.addItem(withTitle: title); output.lastItem?.representedObject = value
        }
        output.autoenablesItems = false; output.menu?.autoenablesItems = false; output.lastItem?.isEnabled = false
        row("Dateiformat", output, "output")
        row("Seiten", duplex, "duplex"); row("Einzug", feeding, "feeding")
        for (title, value) in [("30 Sekunden", "30"), ("60 Sekunden", "60"), ("120 Sekunden", "120"), ("300 Sekunden", "300"), ("Unbegrenzt – mit Stop beenden", "0")] {
            timeout.addItem(withTitle: title); timeout.lastItem?.representedObject = value
        }
        row("Wartezeit ohne neue Seite", timeout, "timeout")
        row("Zuschnitt", crop, "crop"); row("Schräglage", deskew, "deskew")
        for control: NSControl in [output, duplex, feeding, timeout, crop, deskew] {
            control.target = self; control.action = #selector(updateOutputSettings(_:))
        }

        section("Scanfläche und Ausrichtung")
        area.addItems(withTitles: ["Automatische Scanfläche", "Feste Außenmaße"])
        area.item(at: 0)?.representedObject = "automatic"; area.item(at: 1)?.representedObject = "fixed"
        area.target = self; area.action = #selector(updateControls)
        row("Scanfläche", area, "area"); row("Breite quer zum Einzug (mm)", width, "width")
        row("Höhe in Einzugsrichtung (mm)", height, "height"); row("Original", transparent, "transparent")
        transparent.target = self; transparent.action = #selector(updateControls)
        orientation.target = self; orientation.action = #selector(updateControls)
        orientation.autoenablesItems = false; orientation.menu?.autoenablesItems = false
        row("Ausrichtung", orientation, "orientation")
        for popup in [front, back, offset] {
            for (index, title) in ["0° – unverändert", "90° im Uhrzeigersinn", "180°", "270° im Uhrzeigersinn"].enumerated() {
                popup.addItem(withTitle: title); popup.lastItem?.representedObject = String(index * 90)
            }
        }
        row("Vorne / feste Ersatzdrehung", front, "front"); row("Hinten / feste Ersatzdrehung", back, "back")
        row("Druckversatz der Rückseite", offset, "offset")
        referenceButton.title = "Aufrechte Referenz wählen …"; referenceButton.target = self; referenceButton.action = #selector(chooseReference)
        referenceButton.identifier = NSUserInterfaceItemIdentifier("profile.reference"); referenceButton.bezelStyle = .rounded
        referenceButton.frame = NSRect(x: 16, y: y, width: 310, height: 32); content.addSubview(referenceButton)
        clearReferenceButton.title = "Referenz entfernen"; clearReferenceButton.target = self; clearReferenceButton.action = #selector(clearReference)
        clearReferenceButton.identifier = NSUserInterfaceItemIdentifier("profile.clearReference"); clearReferenceButton.bezelStyle = .rounded
        clearReferenceButton.frame = NSRect(x: 340, y: y, width: 260, height: 32); content.addSubview(clearReferenceButton); y += 40
        referenceStatus.frame = NSRect(x: 20, y: y, width: 575, height: 40)
        referenceStatus.font = .systemFont(ofSize: 12); content.addSubview(referenceStatus); y += 44
        hint.frame = NSRect(x: 20, y: y, width: 575, height: 148)
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor; content.addSubview(hint)
        content.frame.size.height = y + 168

        func button(_ title: String, _ x: CGFloat, _ width: CGFloat, _ action: Selector, _ identifier: String) -> NSButton {
            let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier("profile." + identifier)
            button.frame = NSRect(x: x, y: 20, width: width, height: 32); root.addSubview(button); return button
        }
        removeButton.title = "Profil löschen"; removeButton.target = self; removeButton.action = #selector(removeProfile)
        removeButton.identifier = NSUserInterfaceItemIdentifier("profile.remove"); removeButton.bezelStyle = .rounded
        removeButton.frame = NSRect(x: 16, y: 20, width: 130, height: 32); root.addSubview(removeButton)
        let cancel = button("Abbrechen", 290, 110, #selector(cancel), "cancel"); cancel.keyEquivalent = "\u{1b}"
        let save = button("Speichern und verwenden", 410, 195, #selector(save), "save"); save.keyEquivalent = "\r"
        if let active = saved.activeProfile {
            profiles.select(profiles.itemArray.first { ($0.representedObject as? String) == active.id.uuidString }); load(active)
        } else { profiles.selectItem(at: 0); loadLegacy() }
        content.scroll(.zero); panel.center()
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    private func load(_ profile: ScanProfile, legacy: Bool = false) {
        editingLegacy = legacy; current = profile; name.stringValue = profile.name
        profileSettings = profile.scanSettings ?? ProfileScanSettings(settings: snapshot)
        showDestination()
        area.selectItem(at: profile.area.isAutomatic ? 0 : 1)
        width.stringValue = profile.area.widthMM.map { String(format: "%g", $0) } ?? ""
        height.stringValue = profile.area.heightMM.map { String(format: "%g", $0) } ?? ""
        orientation.removeAllItems()
        let modes: [(String, OrientationMode)] = legacy
            ? [("Unverändert", .fixed), ("Automatisch – Epson (bisher)", .epson)]
            : [("Feste Drehung", .fixed), ("Automatisch – macOS", .vision), ("Automatisch – Epson (bisher)", .epson)]
        for (title, mode) in modes {
            orientation.addItem(withTitle: title); orientation.lastItem?.representedObject = mode.rawValue
            if mode == profile.orientation { orientation.select(orientation.lastItem) }
        }
        front.selectItem(at: profile.frontRotation / 90); back.selectItem(at: profile.backRotation / 90)
        offset.selectItem(at: profile.printedBackOffset / 90); transparent.state = profile.isTransparentOriginal ? .on : .off
        updateControls()
    }
    private func loadLegacy() {
        let saved = snapshot.legacyScanSettings ?? ProfileScanSettings(settings: snapshot)
        var profile = ScanProfile(name: "Bisherige Einstellungen")
        profile.scanSettings = saved; profile.orientation = saved.rotate ? .epson : .fixed
        load(profile, legacy: true)
    }
    @objc private func selectProfile() {
        guard let value = profiles.selectedItem?.representedObject as? String else { return }
        if value == "legacy" { loadLegacy(); return }
        if let id = UUID(uuidString: value), let profile = snapshot.profiles.first(where: { $0.id == id }) { load(profile); return }
        if value == "receipts" { load(ScanProfile.receipts(destination: nil)); return }
        let holder = value == "holder"
        var profile = ScanProfile(name: holder ? "Toploader" : "Karte"); profile.orientation = .vision
        if holder { profile.transparentOriginal = true } else { profile.area = ScanArea(widthMM: 63, heightMM: 88) }
        load(profile)
        if holder { area.selectItem(at: 1); updateControls() }
    }
    private var orientationMode: OrientationMode {
        (orientation.selectedItem?.representedObject as? String).flatMap(OrientationMode.init(rawValue:)) ?? .fixed
    }
    @objc private func updateOutputSettings(_ sender: NSControl) {
        if sender === output, let value = output.selectedItem?.representedObject as? String, let format = OutputFormat(rawValue: value) { profileSettings.outputFormat = format }
        if sender === duplex { profileSettings.duplex = duplex.state == .on }
        if sender === feeding { profileSettings.automaticFeeding = feeding.state == .on }
        if sender === timeout, let value = timeout.selectedItem?.representedObject as? String, let seconds = Int(value) { profileSettings.feedingTimeoutSeconds = seconds }
        if sender === crop, crop.isEnabled { profileSettings.crop = crop.state == .on }
        if sender === deskew, deskew.isEnabled { profileSettings.deskew = deskew.state == .on }
        updateControls()
    }
    @objc private func updateControls() {
        let fixed = !editingLegacy && area.indexOfSelectedItem == 1
        let holder = !editingLegacy && transparent.state == .on
        name.isEnabled = !editingLegacy; area.isEnabled = !editingLegacy; transparent.isEnabled = !editingLegacy
        width.isEnabled = fixed; height.isEnabled = fixed
        let mode = orientationMode
        front.isEnabled = !editingLegacy && mode != .epson; back.isEnabled = front.isEnabled
        offset.isEnabled = !editingLegacy && mode == .vision
        for item in orientation.itemArray where (item.representedObject as? String) == "epson" { item.isEnabled = !fixed && !holder }
        referenceButton.isEnabled = !editingLegacy && mode == .vision
        clearReferenceButton.isEnabled = referenceButton.isEnabled && current.referencePrint != nil
        referenceStatus.stringValue = editingLegacy ? "Automatische Scanfläche; unverändert oder bisherige Epson-Drehung nach Auswahl oben."
            : current.referencePrint == nil ? "Optional: aufrechtes Kartenbild, z. B. eine gemeinsame Rückseite."
            : "Lokale Bildreferenz gespeichert – ohne Bilddatei oder Dateipfad."
        removeButton.isEnabled = !editingLegacy && snapshot.profiles.contains { $0.id == current.id }
        output.selectItem(at: profileSettings.automaticFeeding ? 2 : profileSettings.outputFormat == .jpg ? 0 : 1)
        output.isEnabled = !profileSettings.automaticFeeding
        duplex.state = profileSettings.duplex ? .on : .off; feeding.state = profileSettings.automaticFeeding ? .on : .off
        timeout.selectItem(at: timeout.itemArray.firstIndex { ($0.representedObject as? String) == String(profileSettings.feedingTimeoutSeconds) } ?? 2)
        timeout.isEnabled = profileSettings.automaticFeeding
        crop.isEnabled = !fixed && !holder; deskew.isEnabled = crop.isEnabled
        crop.state = (holder || (!fixed && profileSettings.crop)) ? .on : .off
        deskew.state = (!holder && !fixed && profileSettings.deskew) ? .on : .off
        crop.title = holder ? "Zuschnitt – für transparente Hülle erforderlich" : fixed ? "Automatischer Zuschnitt – bei festen Maßen aus" : "Automatischer Zuschnitt"
        deskew.title = holder ? "Schräglagenkorrektur – bei Hüllen aus" : fixed ? "Schräglagenkorrektur – bei festen Maßen aus" : "Schräglagenkorrektur"
        var text = editingLegacy ? "Die bisherigen Einstellungen bleiben ein eigener Eintrag. Sie verwenden automatische Scanfläche; feste Maße, macOS-Ausrichtung und Referenzen stehen in benannten Profilen zur Verfügung."
            : fixed ? "Außenmaße vor der Drehung. Beim Einzelscan schneidet die App die feste Fläche mittig aus dem Papierformat aus; automatischer Randzuschnitt und Schräglagenkorrektur sind aus. Bei festen Maßen bitte feste Drehung oder Automatisch – macOS wählen."
            : "Die automatische Scanfläche übernimmt das erkannte Papierformat. Automatischer Zuschnitt und Schräglagenkorrektur lassen sich oben einstellen. Feste Außenmaße und Referenzen sind für Karten und Hüllen verfügbar. Automatische Höhe ist noch nicht freigegeben."
        if holder { text = "Die Hülle wird mit transparenten Rändern erfasst. Der dafür erforderliche Zuschnitt ist an, Schräglagenkorrektur ist aus. Feste Maße bestimmen die Ausgabegröße vor der Drehung, ohne Strecken. Bei zu kleiner Fläche bleiben die Originale erhalten. Bitte Automatisch – macOS oder feste Drehung wählen." }
        if !editingLegacy && mode == .vision && profileSettings.duplex && (profileSettings.automaticFeeding || holder ? current.feedingMapping : current.icaMapping) == nil {
            text += "\nDie Duplex-Zuordnung dieses Scanwegs ist noch nicht kalibriert. Bis zur Geräteprüfung gelten die festen Ersatzdrehungen."
        } else if !editingLegacy && mode == .vision { text += "\nBei unsicherer Erkennung gelten die festen Ersatzdrehungen. Vorne/hinten bezeichnet die Scannerseite." }
        if profileSettings.automaticFeeding { text += "\nKontinuierliche Scans sammeln die Seiten im Sammlungs-PDF. Die JPG/PDF-Auswahl pro Blatt bleibt für Einzelscans gespeichert." }
        hint.stringValue = text
    }
    @objc private func chooseReference() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.jpeg, .png]; panel.allowsMultipleSelection = false
        panel.message = "Wähle einen scharfen, aufrechten Scan der Karte, z. B. die gemeinsame Pokémon-Rückseite. Erkennung und Bildvergleich bleiben auf diesem Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { current.referencePrint = try ReferenceMatcher.makeReference(url); updateControls() }
        catch { showError("Die Referenz konnte nicht gelesen werden. Bitte ein einzelnes JPG- oder PNG-Bild mit höchstens 16 Megapixeln und 32 MB wählen.") }
    }
    @objc private func clearReference() { current.referencePrint = nil; updateControls() }
    private func showDestination() {
        destination.stringValue = profileSettings.destination ?? ""; destination.toolTip = profileSettings.destination
    }
    @objc private func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.title = "Ablageordner für dieses Profil wählen"; panel.prompt = "Ordner verwenden"
        let draftPath = destination.stringValue
        if !draftPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: draftPath) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isWritableFile(atPath: url.path) else { showError("Der gewählte Ordner ist nicht beschreibbar."); return }
        profileSettings.destination = url.path; showDestination()
    }
    @objc private func save() {
        let path = destination.stringValue
        profileSettings.destination = path.isEmpty ? nil : path
        var next = snapshot
        if editingLegacy {
            profileSettings.rotate = orientationMode == .epson
            do {
                try next.selectProfile(nil); profileSettings.apply(to: &next)
                next.rememberActiveProfileSettings(); try next.validate(); finish(next)
            } catch { showError("Bitte Ablageordner und bisherige Einstellungen prüfen.") }
            return
        }
        var profile = current; profile.name = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.transparentOriginal = transparent.state == .on
        if area.indexOfSelectedItem == 1 {
            guard let width = Double(width.stringValue.replacingOccurrences(of: ",", with: ".")), let height = Double(height.stringValue.replacingOccurrences(of: ",", with: ".")) else { showError("Bitte beide Außenmaße in Millimetern eingeben."); return }
            profile.area = ScanArea(widthMM: width, heightMM: height)
        } else { profile.area = ScanArea() }
        profile.orientation = orientationMode
        profile.frontRotation = front.indexOfSelectedItem * 90; profile.backRotation = back.indexOfSelectedItem * 90
        profile.printedBackOffset = offset.indexOfSelectedItem * 90; profile.scanSettings = profileSettings
        do { try next.saveProfile(profile); finish(next) }
        catch { showError("Bitte Profilnamen, Ablageordner, Drehungen und Maße prüfen. Breite: 50,8–215,9 mm, Höhe: 50,8–297 mm. Bei fester Fläche bitte feste Drehung oder Automatisch – macOS wählen.") }
    }
    @objc private func removeProfile() {
        var next = snapshot
        do { try next.removeProfile(current.id); finish(next) } catch { showError(error.localizedDescription) }
    }
    @objc private func cancel() { finish(nil) }
    private func finish(_ next: ScanSettings?) {
        guard !completed, completion(next) else { return }; completed = true; close()
    }
    func windowWillClose(_ notification: Notification) { if !completed { _ = completion(nil); completed = true } }
    private func showError(_ text: String) { let alert = NSAlert(); alert.messageText = "Profil prüfen"; alert.informativeText = text; alert.runModal() }
}
