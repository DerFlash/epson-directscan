import AppKit
import Testing
@testable import DirectScanCore
@testable import EpsonDirectScan

@Suite(.serialized) @MainActor struct ProfileMenuTests {
    private func item(_ id: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.identifier?.rawValue == id }, "Missing menu item: \(id)")
    }

    @Test func documentShortcutChangesOnlyActiveProfileAndKeepsRawCorrections() throws {
        _ = NSApplication.shared
        let fixture=try StorageTests(),storage=try fixture.store()
        var receipts=ScanProfile(name:"Belege");receipts.orientation = .vision
        let other=ScanProfile(name:"Andere Belege")
        let app=AppDelegate(storage:storage);app.settings=ScanSettings(destination:try fixture.destination().path)
        app.settings.profiles=[receipts,other];app.settings.activeProfileID=receipts.id
        let menu=NSMenu();app.menuNeedsUpdate(menu)
        let documents=try item("profile.quick.documents",in:menu)
        #expect(documents.isEnabled && documents.state == .off)
        menu.performActionForItem(at:menu.index(of:documents))
        #expect(app.settings.separatesDocuments && app.settings.profiles[1].separateDocuments == nil)
        #expect(app.settings.crop && app.settings.deskew)
        #expect(try storage.loadSettings().separatesDocuments)
        app.settings.activeProfileID=nil;app.menuNeedsUpdate(menu)
        #expect(try !item("profile.quick.documents",in:menu).isEnabled)
    }

    @Test func namedQuickSwitchesGroupFolderAndSaveOrientationOnExistingProfile() throws {
        _ = NSApplication.shared
        let fixture = try StorageTests(), storage = try fixture.store()
        var profile = ScanProfile(name: "Karten")
        profile.orientation = .fixed; profile.referencePrint = Data([1, 2]); profile.icaMapping = nil
        var settings = ScanSettings(destination: try fixture.destination().path)
        settings.profiles = [profile]; settings.activeProfileID = profile.id
        let app = AppDelegate(storage: storage); app.settings = settings
        let menu = NSMenu(); app.menuNeedsUpdate(menu)
        let heading = try item("profile.quick.heading", in: menu)
        let folder = try item("profile.quick.destination", in: menu)
        #expect(heading.title.contains("„Karten“") && !heading.isEnabled)
        #expect(menu.index(of: heading) < menu.index(of: folder))
        let orientation = try #require(try item("profile.quick.orientation", in: menu).submenu)
        let index = try #require(orientation.items.firstIndex { ($0.representedObject as? String) == "vision" })
        orientation.performActionForItem(at: index)
        #expect(app.settings.activeProfileID == profile.id && app.settings.profiles.count == 1)
        #expect(app.settings.activeProfile?.orientation == .vision)
        #expect(app.settings.activeProfile?.referencePrint == Data([1, 2]) && app.settings.activeProfile?.icaMapping == nil)
        #expect(app.settings.destination == settings.destination && app.settings.outputFormat == .jpg)
        #expect(try storage.loadSettings().activeProfile?.orientation == .vision)
    }

    @Test func holderMenuShowsForcedCorrectionsAndOnlySupportedOrientationChoices() throws {
        _ = NSApplication.shared
        let fixture = try StorageTests(), storage = try fixture.store()
        var profile = ScanProfile(name: "Toploader")
        profile.area = ScanArea(widthMM: 75, heightMM: 102); profile.transparentOriginal = true; profile.orientation = .vision
        var settings = ScanSettings(destination: try fixture.destination().path)
        settings.profiles = [profile]; settings.activeProfileID = profile.id; settings.crop = false; settings.deskew = true
        let app = AppDelegate(storage: storage); app.settings = settings
        let menu = NSMenu(); app.menuNeedsUpdate(menu)
        let crop = try item("profile.quick.crop", in: menu), deskew = try item("profile.quick.deskew", in: menu)
        #expect(!crop.isEnabled && crop.state == .on && !deskew.isEnabled && deskew.state == .off)
        let orientation = try #require(try item("profile.quick.orientation", in: menu).submenu)
        #expect(!orientation.items.contains { ($0.representedObject as? String) == "epson" && $0.isEnabled })
        let index = try #require(orientation.items.firstIndex { ($0.representedObject as? String) == "fixed" })
        orientation.performActionForItem(at: index)
        #expect(app.settings.activeProfile?.orientation == .fixed)
        #expect(!app.settings.crop && app.settings.deskew)
    }

    @Test func legacyQuickSwitchKeepsSupportedRotationWithoutCreatingProfile() throws {
        _ = NSApplication.shared
        let fixture = try StorageTests(), storage = try fixture.store()
        let app = AppDelegate(storage: storage)
        app.settings = ScanSettings(destination: try fixture.destination().path)
        let menu = NSMenu(); app.menuNeedsUpdate(menu)
        #expect(try item("profile.quick.heading", in: menu).title.contains("Bisherige Einstellungen"))
        let rotation = try item("profile.quick.orientation", in: menu)
        #expect(rotation.isEnabled && rotation.state == .on && rotation.submenu == nil)
        menu.performActionForItem(at: menu.index(of: rotation))
        #expect(!app.settings.rotate && app.settings.activeProfileID == nil && app.settings.profiles.isEmpty)
        #expect(try storage.loadSettings().legacyScanSettings?.rotate == false)
    }
}
