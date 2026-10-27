import Foundation
import Testing
@testable import DirectScanCore
@testable import EpsonDirectScan

private final class HandoffServices: EpsonServices {
    var paused = false
    func acquire() throws { paused = true }
    func restore() throws { paused = false }
}
private final class FakeHelper: NativeHelper {
    var onEvent: ((HelperEvent) -> Void)?
    var onExit: ((Int32) -> Void)?
    var cancelled = false
    var finishRequested = false
    func start() throws {}
    func cancel() { cancelled = true }
    func forceStop() { cancelled = true }
    func finish() { finishRequested = true }
    func emit(_ name: String, _ value: Int? = nil, file: String? = nil) {
        onEvent?(HelperEvent(event: name, value: value, file: file))
    }
    func exit(_ code: Int32 = 0) { onExit?(code) }
}
private final class HelperFactory {
    var roles: [HelperRole] = []
    var helpers: [FakeHelper] = []
    func make(_ role: HelperRole) -> NativeHelper {
        roles.append(role); let helper = FakeHelper(); helpers.append(helper); return helper
    }
}
private final class HandoffSettings { var value: ScanSettings; init(_ value: ScanSettings) { self.value = value } }
private final class HandoffClock { var time: TimeInterval = 0 }
@MainActor private final class HandoffFixture {
    let root: URL
    let storage: ScanStorage
    let services = HandoffServices()
    let factory = HelperFactory()
    let clock = HandoffClock()
    let settings: HandoffSettings
    let controller: ScanCoordinator
    var button: FakeHelper { factory.helpers[0] }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storage = try ScanStorage(root: root.appendingPathComponent("private"))
        let out = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        settings = HandoffSettings(ScanSettings(destination: out.path))
        let factory = self.factory, settings = self.settings, clock = self.clock
        controller = ScanCoordinator(storage: storage, diagnostics: Diagnostics(root: storage.root),
            settings: { settings.value }, services: services, makeHelper: { factory.make($0) },
            conflictingApps: { false }, now: { clock.time })
        controller.start()
    }
    func trigger() {
        button.emit("ready", 1); button.emit("button", 1)
        button.emit("closed", 0); button.exit()
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}
@Suite @MainActor struct HandoffTests {
    @Test func feedingStartsOnlyFromPhysicalButtonAndUnlimitedIdleHasNoWholeSessionDeadline() throws {
        let f = try HandoffFixture()
        f.settings.value.automaticFeeding = true; f.settings.value.feedingTimeoutSeconds = 0
        f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else { Issue.record("Expected automatic feeding"); return }
        #expect(job.settings.automaticFeeding)
        let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        f.settings.value.duplex = true
        #expect(!job.settings.duplex)
        f.clock.time = 10000; f.controller.checkDeadline()
        #expect(!worker.cancelled && !worker.finishRequested)
        #expect(f.controller.busy && f.controller.collecting)
        #expect(f.controller.collectionPages == 0)
    }
    @Test func feedingIdleTimerExcludesTransfersAndResetsAfterProcessedBatch() throws {
        let f = try HandoffFixture()
        f.settings.value.automaticFeeding = true; f.settings.value.feedingTimeoutSeconds = 30
        f.trigger(); let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        f.clock.time = 10; worker.emit("batchBegin", 1)
        f.clock.time = 45; f.controller.checkDeadline()
        #expect(!worker.finishRequested && !worker.cancelled)
        f.clock.time = 50; worker.emit("batchEnd", 1)
        f.clock.time = 79; f.controller.checkDeadline(); #expect(!worker.finishRequested)
        f.clock.time = 80; f.controller.checkDeadline(); #expect(worker.finishRequested && !worker.cancelled)
    }
    @Test func collectionPublishesOnlyAfterEndCloseAndExitAndRejectsLatePages() throws {
        let f = try HandoffFixture(), image = try StorageTests()
        f.settings.value.automaticFeeding = true; f.settings.value.duplex = true
        f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else { Issue.record("Expected feeding"); return }
        let worker = f.factory.helpers[1]; worker.emit("ready", 1); worker.emit("batchBegin", 1)
        for index in 1...2 {
            let name = "page-\(index).jpg"; try image.jpeg(job.directory.appendingPathComponent(name))
            worker.onEvent?(HelperEvent(event: "page", value: index, file: name, sheet: 1, side: index-1))
        }
        worker.emit("batchEnd", 1)
        #expect(f.controller.collectionPages == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: job.destination.path).isEmpty)
        f.controller.finishCollection(); #expect(worker.finishRequested)
        worker.emit("end", 0); worker.emit("closed", 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: job.destination.path).isEmpty)
        worker.exit()
        #expect(f.controller.lastFile?.pathExtension == "pdf")
        #expect(try !f.storage.hasUnfinishedJobs())
        #expect(f.factory.roles.last == .button)
        worker.onEvent?(HelperEvent(event: "page", value: 3, file: "late.jpg", sheet: 2, side: 0))
        #expect(f.controller.imagesSaved == 2)
    }
    @Test func failedCollectionRetainsImagesAndCannotRearm() throws {
        let f = try HandoffFixture(), image = try StorageTests()
        f.settings.value.automaticFeeding = true; f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else { Issue.record("Expected feeding"); return }
        let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        let source = job.directory.appendingPathComponent("page.jpg"); try image.jpeg(source)
        worker.onEvent?(HelperEvent(event: "page", value: 1, file: "page.jpg", sheet: 1, side: 0))
        worker.emit("error", 99); worker.emit("end", 0); worker.emit("closed", 0); worker.exit(1)
        #expect(f.controller.policy.phase == .error)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(f.factory.roles.count == 2)
    }
    @Test func partialFinalCardIsSavedButExplicitlyMarkedIncomplete() throws {
        let f = try HandoffFixture(), image = try StorageTests()
        f.settings.value.automaticFeeding = true; f.settings.value.duplex = true; f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else { Issue.record("Expected feeding"); return }
        let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        try image.jpeg(job.directory.appendingPathComponent("front.jpg"))
        worker.onEvent?(HelperEvent(event: "page", value: 1, file: "front.jpg", sheet: 1, side: 0))
        worker.emit("end", 0); worker.emit("closed", 0); worker.exit()
        #expect(f.controller.lastCollectionIncomplete)
        f.factory.helpers.last?.emit("ready", 1)
        #expect(f.controller.message.contains("unvollständig"))
        #expect(f.controller.lastFile?.pathExtension == "pdf")
    }
    @Test func pageAfterEndCannotFinalizeOrAppendToANewCollection() throws {
        let f = try HandoffFixture(); f.settings.value.automaticFeeding = true; f.trigger()
        let worker = f.factory.helpers[1]; worker.emit("ready", 1); worker.emit("end", 0)
        worker.onEvent?(HelperEvent(event: "page", value: 1, file: "late.jpg", sheet: 1, side: 0))
        worker.emit("closed", 0); worker.exit()
        #expect(f.controller.policy.phase == .error)
        #expect(f.factory.roles.count == 2)
        #expect(try f.storage.hasUnfinishedJobs())
    }
    @Test func finishDeadlineSurvivesTheFinalBatchCallback() throws {
        let f = try HandoffFixture(); f.settings.value.automaticFeeding = true; f.trigger()
        let worker = f.factory.helpers[1]; worker.emit("ready", 1); worker.emit("batchBegin", 1)
        f.controller.finishCollection(); worker.emit("batchEnd", 1)
        f.clock.time = 25; f.controller.checkDeadline()
        #expect(worker.cancelled)
        #expect(f.controller.policy.phase == .error)
    }
    @Test func emptyFinishedCollectionCanPauseForQuitWithoutDiscardingUnexpectedFiles() throws {
        let f = try HandoffFixture(); f.settings.value.automaticFeeding = true; f.trigger()
        let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        f.controller.finishCollection(pauseAfter: true)
        worker.emit("end", 0); worker.emit("closed", 0); worker.exit()
        #expect(!f.controller.listening && f.controller.sessionReleased && !f.services.paused)
        #expect(try !f.storage.hasUnfinishedJobs())
        #expect(f.factory.roles.count == 2)
    }
    @Test func quitCanJoinAnAlreadyFinishingCollectionWithoutRearming() throws {
        let f = try HandoffFixture(); f.settings.value.automaticFeeding = true; f.settings.value.feedingTimeoutSeconds = 30; f.trigger()
        let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        f.clock.time = 30; f.controller.checkDeadline()
        #expect(worker.finishRequested)
        f.controller.finishCollection(pauseAfter: true)
        worker.emit("end", 0); worker.emit("closed", 0); worker.exit()
        #expect(f.factory.roles.count == 2)
        #expect(!f.controller.listening && f.controller.sessionReleased && !f.services.paused)
    }
    @Test func buttonAfterCloseIsNeverTreatedAsANewPhysicalTrigger() throws {
        let f = try HandoffFixture()
        f.button.emit("ready", 1); f.button.emit("closed", 0)
        f.button.emit("button", 1); f.button.exit()
        #expect(f.factory.roles == [.button])
        #expect(f.controller.policy.phase == .error)
    }
    @Test func startupAndEarlyOrWrongButtonsNeverStartAScan() throws {
        let f = try HandoffFixture()
        f.button.emit("button", 1)
        f.button.emit("ready", 1)
        f.button.emit("button", 2)
        #expect(f.factory.roles == [.button])
        #expect(f.controller.policy.phase == .ready)
        #expect(f.controller.buttonEvents == 0)
    }
    @Test func buttonMustBeFollowedByConfirmedCloseAndProcessExit() throws {
        let f = try HandoffFixture()
        f.button.emit("ready", 1); f.button.emit("button", 1); f.button.emit("button", 1)
        #expect(f.controller.busy)
        #expect(f.controller.buttonEvents == 1)
        f.button.emit("closed", 0)
        #expect(f.factory.roles.count == 1)
        f.button.exit()
        #expect(f.factory.roles.count == 2)
        #expect(f.services.paused)
        if case .scan = f.factory.roles[1] {} else { Issue.record("Expected authorized scan worker") }
    }
    @Test func missingCloseConfirmationBlocksScanningAndServiceRestore() throws {
        let f = try HandoffFixture()
        f.button.emit("ready", 1); f.button.emit("button", 1); f.button.exit()
        #expect(f.factory.roles == [.button])
        #expect(f.controller.policy.phase == .error)
        #expect(f.services.paused)
        #expect(!f.controller.sessionReleased)
    }
    @Test func pausedReceiverCannotLaunchAQueuedScanOrRestoreBeforeExit() throws {
        let f = try HandoffFixture()
        f.button.emit("ready", 1)
        f.controller.pause()
        f.button.emit("button", 1); f.button.emit("closed", 0)
        #expect(f.services.paused)
        f.button.exit()
        #expect(!f.services.paused)
        #expect(f.controller.sessionReleased)
        #expect(f.factory.roles == [.button])
    }
    @Test func settingsAreFrozenAtTheAcceptedPhysicalButton() throws {
        let f = try HandoffFixture()
        let original = f.settings.value
        f.button.emit("ready", 1); f.button.emit("button", 1)
        f.settings.value.destination = "/another-folder"
        f.settings.value.crop = false
        f.button.emit("closed", 0); f.button.exit()
        #expect(f.factory.roles.last == .scan(original))
    }
    @Test func completedScanRearmsOnlyAfterWorkerReleaseAndExit() throws {
        let f = try HandoffFixture(); f.trigger()
        let worker = f.factory.helpers[1]
        worker.emit("file", 1, file: "Karte_sample.jpg"); worker.emit("complete", 1)
        #expect(f.factory.roles.count == 2)
        worker.emit("closed", 0)
        #expect(f.factory.roles.count == 2)
        worker.exit()
        #expect(f.factory.roles.count == 3)
        #expect(f.controller.imagesSaved == 1)
        f.button.emit("button", 1); worker.emit("file", 2, file: "late.jpg")
        #expect(f.controller.imagesSaved == 1)
        #expect(f.controller.buttonEvents == 1)
        f.factory.helpers[2].emit("ready", 1)
        #expect(f.controller.policy.phase == .ready)
    }
    @Test func workerFailurePreservesPendingJobAndNeverRearms() throws {
        let f = try HandoffFixture(); f.trigger()
        _ = try f.storage.beginJob(settings: f.settings.value)
        let worker = f.factory.helpers[1]
        worker.emit("error", 7); worker.emit("closed", 0); worker.exit(1)
        #expect(f.controller.policy.phase == .error)
        #expect(f.factory.roles.count == 2)
        #expect(try f.storage.hasUnfinishedJobs())
        #expect(!f.services.paused)
    }
    @Test func timeoutCancelsAndNeverReplaysTheButton() throws {
        let f = try HandoffFixture()
        f.clock.time = 30; f.controller.checkDeadline()
        #expect(f.button.cancelled)
        f.button.emit("ready", 1); f.button.emit("button", 1)
        f.button.emit("closed", 0); f.button.exit()
        #expect(f.controller.policy.phase == .error)
        #expect(f.factory.roles == [.button])
    }
}
