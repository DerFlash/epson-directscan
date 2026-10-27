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
    func start() throws {}
    func cancel() { cancelled = true }
    func forceStop() { cancelled = true }
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
