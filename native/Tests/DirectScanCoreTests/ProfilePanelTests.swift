import AppKit
import Testing
@testable import DirectScanCore
@testable import EpsonDirectScan

@Suite(.serialized) @MainActor struct ProfilePanelTests {
    private func control<T: NSView>(_ id: String, in panel: ProfilePanel, as type: T.Type = T.self) throws -> T {
        func find(_ view: NSView) -> T? {
            if view.identifier?.rawValue == id { return view as? T }
            return view.subviews.lazy.compactMap(find).first
        }
        return try #require(panel.window?.contentView.flatMap(find), "Missing control: \(id)")
    }

    private func choose(_ popup: NSPopUpButton, value: String) throws {
        try #require(popup.isEnabled, "Disabled control: \(popup.identifier?.rawValue ?? "popup")")
        let index = try #require(popup.itemArray.firstIndex { ($0.representedObject as? String) == value })
        try #require(popup.item(at: index)?.isEnabled == true)
        popup.selectItem(at: index)
        if let action = popup.action { NSApp.sendAction(action, to: popup.target, from: popup) }
    }

    private func settings(profile: ScanProfile) -> ScanSettings {
        var result = ScanSettings(destination: "/tmp/cards")
        result.profiles = [profile]; result.activeProfileID = profile.id
        return result
    }

    @Test func separateDocumentsEditorSavesOnlySelectedProfileAndCancelDiscardsIt() throws {
        _ = NSApplication.shared
        var receipt=ScanProfile(name:"Belege");receipt.orientation = .vision
        var saved:ScanSettings?
        let panel=ProfilePanel(settings:settings(profile:receipt)) {saved=$0;return true}
        defer {panel.close()}
        let separate:NSButton=try control("profile.documents",in:panel)
        #expect(separate.isEnabled && separate.state == .off)
        separate.performClick(nil)
        #expect(try !control("profile.crop",in:panel,as:NSButton.self).isEnabled)
        try control("profile.save",in:panel,as:NSButton.self).performClick(nil)
        #expect(saved?.activeProfile?.separateDocuments == true && saved?.activeProfileID == receipt.id)
        #expect(saved?.crop == true && saved?.deskew == true)
        var cancelled:ScanSettings?
        let draft=ProfilePanel(settings:try #require(saved)) {cancelled=$0;return true}
        defer {draft.close()}
        try control("profile.documents",in:draft,as:NSButton.self).performClick(nil)
        try control("profile.cancel",in:draft,as:NSButton.self).performClick(nil)
        #expect(cancelled == nil && saved?.separatesDocuments == true)
    }
    @Test func documentModeKeepsIndividualFormatAvailableDuringContinuousFeeding() throws {
        _ = NSApplication.shared
        var profile=ScanProfile(name:"Belege");profile.orientation = .vision;profile.separateDocuments=true
        var initial=settings(profile:profile);initial.automaticFeeding=true
        let panel=ProfilePanel(settings:initial) {_ in true};defer {panel.close()}
        let output:NSPopUpButton=try control("profile.output",in:panel)
        #expect(output.isEnabled && output.selectedItem?.representedObject as? String=="jpg")
    }

    @Test func saveEditsAllOutputChoicesAndGeometryWithoutReplacingIdentityOrReferences() throws {
        _ = NSApplication.shared
        var originalProfile = ScanProfile(name: "Karten")
        originalProfile.orientation = .vision
        originalProfile.referencePrint = Data([1, 2, 3])
        originalProfile.icaMapping = nil
        let initial = settings(profile: originalProfile)
        var result: ScanSettings?
        let panel = ProfilePanel(settings: initial) { result = $0; return true }
        defer { panel.close() }

        try control("profile.destination", in: panel, as: NSTextField.self).stringValue = "/tmp/new-cards"
        try control("profile.name", in: panel, as: NSTextField.self).stringValue = "Karten neu"
        try choose(control("profile.output", in: panel), value: "pdf")
        try control("profile.duplex", in: panel, as: NSButton.self).performClick(nil)
        try control("profile.feeding", in: panel, as: NSButton.self).performClick(nil)
        try choose(control("profile.timeout", in: panel), value: "0")
        try control("profile.crop", in: panel, as: NSButton.self).performClick(nil)
        try control("profile.deskew", in: panel, as: NSButton.self).performClick(nil)
        try choose(control("profile.area", in: panel), value: "fixed")
        try control("profile.width", in: panel, as: NSTextField.self).stringValue = "69"
        try control("profile.height", in: panel, as: NSTextField.self).stringValue = "94"
        try choose(control("profile.offset", in: panel), value: "270")
        try choose(control("profile.orientation", in: panel), value: "fixed")
        try choose(control("profile.front", in: panel), value: "90")
        try choose(control("profile.back", in: panel), value: "180")
        #expect(result == nil)
        try control("profile.save", in: panel, as: NSButton.self).performClick(nil)

        let saved = try #require(result)
        let profile = try #require(saved.activeProfile)
        #expect(profile.id == originalProfile.id && saved.profiles.count == 1)
        #expect(profile.name == "Karten neu" && profile.referencePrint == Data([1, 2, 3]))
        #expect(profile.icaMapping == nil && profile.feedingMapping == originalProfile.feedingMapping)
        #expect(profile.area == ScanArea(widthMM: 69, heightMM: 94))
        #expect(profile.orientation == .fixed && profile.frontRotation == 90 && profile.backRotation == 180 && profile.printedBackOffset == 270)
        #expect(saved.destination == "/tmp/new-cards" && saved.outputFormat == .pdf)
        #expect(saved.duplex && saved.automaticFeeding && saved.feedingTimeoutSeconds == 0)
        #expect(!saved.crop && !saved.deskew && saved.rotate)
        #expect(profile.scanSettings == ProfileScanSettings(settings: saved))
    }

    @Test func collectionShowsEffectivePDFAndRestoresPerSheetPreference() throws {
        _ = NSApplication.shared
        var result: ScanSettings?
        let panel = ProfilePanel(settings: settings(profile: ScanProfile(name: "Belege"))) { result = $0; return true }
        defer { panel.close() }
        let output: NSPopUpButton = try control("profile.output", in: panel)
        let timeout: NSPopUpButton = try control("profile.timeout", in: panel)
        #expect(!timeout.isEnabled)
        try choose(output, value: "pdf")
        let feeding: NSButton = try control("profile.feeding", in: panel)
        feeding.performClick(nil)
        #expect(!output.isEnabled && output.selectedItem?.representedObject as? String == "collection")
        #expect(timeout.isEnabled)
        feeding.performClick(nil)
        #expect(output.isEnabled && output.selectedItem?.representedObject as? String == "pdf")
        #expect(!timeout.isEnabled)
        try control("profile.save", in: panel, as: NSButton.self).performClick(nil)
        #expect(result?.outputFormat == .pdf && result?.automaticFeeding == false)
    }

    @Test func cancelDiscardsOutputAndReferenceDrafts() throws {
        _ = NSApplication.shared
        var profile = ScanProfile(name: "Karte"); profile.orientation = .vision; profile.referencePrint = Data([1])
        var completions: [ScanSettings?] = []
        let panel = ProfilePanel(settings: settings(profile: profile)) { completions.append($0); return true }
        defer { panel.close() }
        try control("profile.destination", in: panel, as: NSTextField.self).stringValue = "/tmp/draft"
        try control("profile.duplex", in: panel, as: NSButton.self).performClick(nil)
        try control("profile.clearReference", in: panel, as: NSButton.self).performClick(nil)
        #expect(completions.isEmpty)
        try control("profile.cancel", in: panel, as: NSButton.self).performClick(nil)
        #expect(completions.count == 1 && completions[0] == nil)
        #expect(profile.referencePrint == Data([1]))
    }

    @Test func legacySaveEditsExistingSettingsWithoutCreatingProfile() throws {
        _ = NSApplication.shared
        var profile = ScanProfile(name: "Karte")
        profile.area = ScanArea(widthMM: 63, heightMM: 88); profile.orientation = .vision; profile.referencePrint = Data([2])
        var initial = settings(profile: profile)
        var legacy = ScanSettings(destination: "/tmp/legacy")
        legacy.outputFormat = .pdf; legacy.rotate = false
        initial.legacyScanSettings = ProfileScanSettings(settings: legacy)
        var result: ScanSettings?
        let panel = ProfilePanel(settings: initial) { result = $0; return true }
        defer { panel.close() }
        try choose(control("profile.selection", in: panel), value: "legacy")
        #expect(try !control("profile.name", in: panel, as: NSTextField.self).isEnabled)
        #expect(try !control("profile.area", in: panel, as: NSPopUpButton.self).isEnabled)
        #expect(try !control("profile.transparent", in: panel, as: NSButton.self).isEnabled)
        let orientation: NSPopUpButton = try control("profile.orientation", in: panel)
        #expect(!orientation.itemArray.contains { ($0.representedObject as? String) == "vision" })
        try control("profile.destination", in: panel, as: NSTextField.self).stringValue = "/tmp/legacy-new"
        try choose(control("profile.output", in: panel), value: "jpg")
        try control("profile.duplex", in: panel, as: NSButton.self).performClick(nil)
        try control("profile.feeding", in: panel, as: NSButton.self).performClick(nil)
        try choose(control("profile.timeout", in: panel), value: "30")
        try control("profile.crop", in: panel, as: NSButton.self).performClick(nil)
        try control("profile.deskew", in: panel, as: NSButton.self).performClick(nil)
        try choose(orientation, value: "epson")
        try control("profile.save", in: panel, as: NSButton.self).performClick(nil)
        let saved = try #require(result)
        #expect(saved.activeProfileID == nil && saved.profiles.count == 1)
        #expect(saved.profiles[0].id == profile.id && saved.profiles[0].referencePrint == Data([2]))
        #expect(saved.profiles[0].area == ScanArea(widthMM: 63, heightMM: 88))
        #expect(saved.destination == "/tmp/legacy-new" && saved.outputFormat == .jpg)
        #expect(saved.duplex && saved.automaticFeeding && saved.feedingTimeoutSeconds == 30)
        #expect(!saved.crop && !saved.deskew && saved.rotate)
        #expect(saved.legacyScanSettings == ProfileScanSettings(settings: saved))
        #expect(saved.profiles[0].scanSettings?.destination == "/tmp/cards")
    }

    @Test func inactiveNamedProfilesDoNotReplaceLegacyEditorSelection() throws {
        _ = NSApplication.shared
        var initial = ScanSettings(destination: "/tmp/legacy")
        initial.profiles = [ScanProfile(name: "Karte")]
        let panel = ProfilePanel(settings: initial) { _ in true }
        defer { panel.close() }
        let selection: NSPopUpButton = try control("profile.selection", in: panel)
        #expect(selection.selectedItem?.representedObject as? String == "legacy")
        #expect(try control("profile.destination", in: panel, as: NSTextField.self).stringValue == "/tmp/legacy")
    }

    @Test func duplicateAndLegacyNamedProfilesRemainSelectableByIdentity() throws {
        _ = NSApplication.shared
        var legacyNamed = ScanProfile(name: "Bisherige Einstellungen")
        legacyNamed.referencePrint = Data([1])
        var first = ScanProfile(name: "Belege"), second = ScanProfile(name: "Belege")
        first.referencePrint = Data([2]); second.referencePrint = Data([3])
        var initial = ScanSettings(destination: "/tmp/duplicates")
        initial.profiles = [legacyNamed, first, second]; initial.activeProfileID = second.id
        var result: ScanSettings?
        let panel = ProfilePanel(settings: initial) { result = $0; return true }
        defer { panel.close() }
        let selection: NSPopUpButton = try control("profile.selection", in: panel)
        #expect(selection.numberOfItems == 7)
        #expect(selection.selectedItem?.representedObject as? String == second.id.uuidString)
        #expect(selection.itemArray.contains { ($0.representedObject as? String) == "legacy" })
        #expect(Set(selection.itemTitles).count == 7)
        for profile in [legacyNamed, second, first] {
            try choose(selection, value: profile.id.uuidString)
            #expect(try control("profile.name", in: panel, as: NSTextField.self).stringValue == profile.name)
        }
        try control("profile.destination", in: panel, as: NSTextField.self).stringValue = "/tmp/first-belege"
        try control("profile.save", in: panel, as: NSButton.self).performClick(nil)
        let saved = try #require(result)
        #expect(saved.activeProfileID == first.id && saved.profiles.count == 3)
        #expect(saved.activeProfile?.referencePrint == Data([2]) && saved.destination == "/tmp/first-belege")
        #expect(saved.profiles.map(\.name) == ["Bisherige Einstellungen", "Belege", "Belege"])
        #expect(saved.profiles.first { $0.id == second.id }?.referencePrint == Data([3]))
    }

    @Test func unchangedDestinationWithTrailingSpaceKeepsExactFolder() throws {
        _ = NSApplication.shared
        let fixture = try StorageTests(), storage = try fixture.store()
        let destination = try fixture.destination("output ")
        let shortenedSibling = try fixture.destination("output")
        var initial = ScanSettings(destination: destination.path)
        let profile = ScanProfile(name: "Belege")
        initial.profiles = [profile]; initial.activeProfileID = profile.id
        var result: ScanSettings?
        let panel = ProfilePanel(settings: initial) { result = $0; return true }
        defer { panel.close() }
        #expect(try control("profile.destination", in: panel, as: NSTextField.self).stringValue == destination.path)
        try control("profile.save", in: panel, as: NSButton.self).performClick(nil)
        let saved = try #require(result)
        #expect(saved.destination == destination.path && saved.destination != shortenedSibling.path)
        try storage.saveSettings(saved, validatingDestination: true)
        #expect(try storage.loadSettings().destination == destination.path)
    }

    @Test func forcedCorrectionsShowEffectiveStatesAndRetainRawPreferences() throws {
        _ = NSApplication.shared
        var profile = ScanProfile(name: "Toploader")
        profile.area = ScanArea(widthMM: 75, heightMM: 102); profile.orientation = .vision
        var result: ScanSettings?
        let panel = ProfilePanel(settings: settings(profile: profile)) { result = $0; return true }
        defer { panel.close() }
        let crop: NSButton = try control("profile.crop", in: panel)
        let deskew: NSButton = try control("profile.deskew", in: panel)
        #expect(!crop.isEnabled && crop.state == .off && !deskew.isEnabled && deskew.state == .off)
        try control("profile.transparent", in: panel, as: NSButton.self).performClick(nil)
        #expect(!crop.isEnabled && crop.state == .on && !deskew.isEnabled && deskew.state == .off)
        try control("profile.save", in: panel, as: NSButton.self).performClick(nil)
        #expect(result?.crop == true && result?.deskew == true && result?.activeProfile?.isTransparentOriginal == true)
    }

    @Test func footerActionsStayOutsideScrollableForm() throws {
        _ = NSApplication.shared
        let panel = ProfilePanel(settings: ScanSettings()) { _ in true }
        defer { panel.close() }
        let save: NSButton = try control("profile.save", in: panel)
        let cancel: NSButton = try control("profile.cancel", in: panel)
        let scroll: NSScrollView = try control("profile.scroll", in: panel)
        #expect(save.superview === panel.window?.contentView && cancel.superview === panel.window?.contentView)
        #expect(save.frame.minY >= 0 && save.frame.maxY <= scroll.frame.minY)
        #expect(scroll.documentView!.frame.height > scroll.contentView.bounds.height)
    }
}
