import Foundation
import Testing
@testable import DirectScanCore

@Suite struct ProfileSettingsTests {
    @Test func receiptSwitchRestoresCardsAcrossRestartAndRemembersMenuChanges() throws {
        var cards = ScanProfile(name: "Karten")
        cards.area = ScanArea(widthMM: 69, heightMM: 94)
        cards.referencePrint = Data([1, 2, 3])
        let receipts = ScanProfile.receipts(destination: "/tmp/Belegeingang")
        var settings = ScanSettings(destination: "/tmp/Karten")
        settings.duplex = true
        settings.profiles = [cards, receipts]; settings.activeProfileID = cards.id
        try settings.selectProfile(receipts.id)
        #expect(settings.destination == "/tmp/Belegeingang")
        #expect(settings.outputFormat == .pdf && !settings.duplex && !settings.automaticFeeding)
        #expect(settings.activeProfile?.area.isAutomatic == true)
        #expect(settings.driverCrop && settings.driverDeskew)
        settings.destination = "/tmp/Belege-neu"
        settings.automaticFeeding = true; settings.feedingTimeoutSeconds = 60
        settings = try JSONDecoder().decode(ScanSettings.self, from: JSONEncoder().encode(settings))
        try settings.selectProfile(cards.id)
        #expect(settings.destination == "/tmp/Karten")
        #expect(settings.outputFormat == .jpg && settings.duplex && !settings.automaticFeeding)
        #expect(settings.activeProfile?.area == ScanArea(widthMM: 69, heightMM: 94))
        #expect(settings.activeProfile?.referencePrint == Data([1, 2, 3]))
        try settings.selectProfile(receipts.id)
        #expect(settings.destination == "/tmp/Belege-neu")
        #expect(settings.outputFormat == .pdf && settings.automaticFeeding && settings.feedingTimeoutSeconds == 60)
    }

    @Test func legacyAndOldProfilesKeepTheirOwnChoices() throws {
        let old = ScanProfile(name: "Altes Profil")
        let receipts = ScanProfile.receipts(destination: "/tmp/Belege")
        var settings = ScanSettings(destination: "/tmp/Alt")
        settings.profiles = [old, receipts]
        try settings.selectProfile(old.id)
        #expect(settings.destination == "/tmp/Alt" && settings.outputFormat == .jpg)
        settings.destination = "/tmp/Karten"; settings.crop = false
        try settings.selectProfile(receipts.id)
        try settings.selectProfile(nil)
        #expect(settings.destination == "/tmp/Alt" && settings.outputFormat == .jpg && settings.crop)
        try settings.selectProfile(old.id)
        #expect(settings.destination == "/tmp/Karten" && !settings.crop)
    }

    @Test func invalidProfileSelectionDoesNotChangeSettings() throws {
        var settings = ScanSettings(destination: "/tmp/Karten")
        let receipts = ScanProfile.receipts(destination: "relative/Belege")
        settings.profiles = [receipts]
        let before = settings
        #expect(throws: (any Error).self) { try settings.selectProfile(UUID()) }
        #expect(settings == before)
        #expect(throws: (any Error).self) { try settings.selectProfile(receipts.id) }
        #expect(settings == before)
    }

    @Test func savingActiveProfileAppliesEditedDestinationWithoutOverwritingIt() throws {
        let receipts = ScanProfile.receipts(destination: "/tmp/Belege")
        var settings = ScanSettings(destination: "/tmp/Karten")
        settings.profiles = [receipts]
        try settings.selectProfile(receipts.id)
        var edited = try #require(settings.activeProfile)
        edited.scanSettings?.destination = "/tmp/Belege-neu"
        edited.scanSettings?.outputFormat = .jpg
        try settings.saveProfile(edited)
        #expect(settings.destination == "/tmp/Belege-neu" && settings.outputFormat == .jpg)
        try settings.selectProfile(nil)
        #expect(settings.destination == "/tmp/Karten")
        try settings.selectProfile(receipts.id)
        #expect(settings.destination == "/tmp/Belege-neu" && settings.outputFormat == .jpg)
    }

    @Test func removingActiveReceiptProfileRestoresLegacyChoices() throws {
        var settings = ScanSettings(destination: "/tmp/Karten")
        settings.duplex = true
        let receipts = ScanProfile.receipts(destination: "/tmp/Belege")
        try settings.saveProfile(receipts)
        #expect(settings.destination == "/tmp/Belege" && settings.outputFormat == .pdf)
        try settings.removeProfile(receipts.id)
        #expect(settings.activeProfileID == nil && settings.profiles.isEmpty)
        #expect(settings.destination == "/tmp/Karten" && settings.outputFormat == .jpg && settings.duplex)
    }

    @Test func upgradeWithActiveNamedCardProfileSeedsLegacyBeforeAddingReceipts() throws {
        let cards = ScanProfile(name: "Karten")
        var settings = ScanSettings(destination: "/tmp/Karten")
        settings.profiles = [cards]; settings.activeProfileID = cards.id; settings.duplex = true
        // Old schema-3 profiles have no per-profile or legacy output snapshots.
        settings = try JSONDecoder().decode(ScanSettings.self, from: JSONEncoder().encode(settings))
        let receipts = ScanProfile.receipts(destination: "/tmp/Belege")
        try settings.saveProfile(receipts)
        try settings.removeProfile(receipts.id)
        #expect(settings.destination == "/tmp/Karten" && settings.outputFormat == .jpg && settings.duplex)
    }

    @Test func unavailableReceiptFolderCannotReplacePersistedActiveProfile() throws {
        let fixture = try StorageTests(), store = try fixture.store(), folder = try fixture.destination()
        var previous = ScanSettings(destination: folder.path)
        let cards = ScanProfile(name: "Karten")
        previous.profiles = [cards]; previous.activeProfileID = cards.id
        try store.saveSettings(previous)
        for destination in [nil, folder.appendingPathComponent("missing").path] as [String?] {
            var candidate = previous
            try candidate.saveProfile(ScanProfile.receipts(destination: destination))
            #expect(throws: (any Error).self) { try store.saveSettings(candidate, validatingDestination: true) }
            #expect(try store.loadSettings() == previous)
        }
    }

    @Test func chosenReceiptProfileExportsPDFToItsFolderAndFreezesJobDestination() throws {
        let fixture = try StorageTests(), store = try fixture.store()
        let cardFolder = try fixture.destination("cards"), receiptFolder = try fixture.destination("receipts")
        var receipts = ScanProfile.receipts(destination: receiptFolder.path)
        // Test export routing independently from OCR.
        receipts.orientation = .fixed
        var settings = ScanSettings(destination: cardFolder.path)
        settings.profiles = [receipts]
        try settings.selectProfile(receipts.id)
        let job = try store.beginJob(settings: settings)
        try settings.selectProfile(nil)
        let source = job.directory.appendingPathComponent("input.jpg")
        try fixture.jpeg(source, width: 100, height: 200)
        try store.stage(source: source, job: job, sheet: 1, side: .front)
        try store.complete(job: job, reason: .completed)
        try store.prepareImages(job: job)
        let output = try store.export(job: job)
        #expect(output.count == 1)
        #expect(output[0].pathExtension == "pdf")
        #expect(output[0].deletingLastPathComponent().path == receiptFolder.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cardFolder.path).isEmpty)
    }
}
