import Foundation
import ImageCaptureCore
import Testing
@testable import DirectScanCore
@testable import EpsonDirectScan

private final class FakeServices: EpsonServices {
    var paused = false
    func acquire() throws { paused = true }
    func restore() throws { paused = false }
}
private final class FakeDevice: ICScannerDevice {
    var openSession = false
    var closeRequested = false
    var scanRequested = false
    let feeder = EmptyFeeder()
    override var name: String? { "EPSON ES-C320W" }
    override var transportType: String? { "ICTransportTypeUSB" }
    override var hasOpenSession: Bool { openSession }
    override var selectedFunctionalUnit: ICScannerFunctionalUnit { feeder }
    override func requestOpenSession() {}
    override func requestCloseSession() { closeRequested = true }
    override func requestScan() { scanRequested = true }
}
private final class EmptyFeeder: ICScannerFunctionalUnitDocumentFeeder {
    override var documentLoaded: Bool { false }
}
private final class FakeBrowser: ICDeviceBrowser {
    let device = FakeDevice()
    override var devices: [ICDevice]? { [device] }
    override func start() {}
    override func stop() {}
}
private final class TestClock { var time: TimeInterval = 0 }
@MainActor private final class AdapterFixture {
    let root: URL
    let services = FakeServices()
    let browser = FakeBrowser()
    let clock = TestClock()
    let controller: ScannerController
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try ScanStorage(root: root.appendingPathComponent("private"))
        let out = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let browser = self.browser, services = self.services, clock = self.clock
        controller = ScannerController(storage: storage, diagnostics: Diagnostics(root: storage.root),
            settings: { ScanSettings(destination: out.path) }, services: services,
            makeBrowser: { browser }, conflictingApps: { false }, now: { clock.time })
        controller.start()
        controller.deviceBrowser(browser, didAdd: browser.device, moreComing: false)
        browser.device.openSession = true
        controller.device(browser.device, didOpenSessionWithError: nil)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}
@Suite @MainActor struct AdapterTests {
    @Test func authorizedWorkerCannotScanBeforeReadyOrWithoutPaper() throws {
        let f = try AdapterFixture()
        var completed: Int?
        f.controller.onScanFinished = { completed = $0 }
        f.controller.scanAuthorized()
        #expect(!f.browser.device.scanRequested)
        #expect(completed == nil)
        f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
        #expect(!f.browser.device.scanRequested)
        f.controller.scanAuthorized()
        #expect(completed == 0)
        #expect(!f.browser.device.scanRequested)
        f.controller.pause()
        f.controller.device(f.browser.device, didCloseSessionWithError: nil)
    }
    @Test func intermediateUnitNotificationWaitsForTheRequestedFeeder() throws {
        let f = try AdapterFixture()
        f.controller.scannerDevice(f.browser.device, didSelect: ICScannerFunctionalUnit(), error: nil)
        #expect(f.controller.policy.phase == .searching)
        #expect(!f.browser.device.closeRequested)
        f.controller.scannerDevice(f.browser.device, didSelect: ICScannerFunctionalUnitDocumentFeeder(), error: nil)
        #expect(f.controller.policy.phase == .ready)
        f.controller.pause()
        f.browser.device.openSession = false
        f.controller.device(f.browser.device, didCloseSessionWithError: nil)
    }
    @Test func epsonServicesStayPausedUntilSuccessfulCloseAcknowledgement() throws {
        let f = try AdapterFixture()
        #expect(f.services.paused)
        f.controller.pause()
        #expect(f.browser.device.closeRequested)
        #expect(f.services.paused)
        #expect(f.controller.busy)
        f.browser.device.openSession = false
        f.controller.device(f.browser.device, didCloseSessionWithError: nil)
        #expect(!f.services.paused)
        #expect(!f.controller.busy)
    }
    @Test func closeErrorCannotBeReportedAsReleasedOrRestarted() throws {
        let f = try AdapterFixture()
        f.controller.pause()
        f.controller.device(f.browser.device, didCloseSessionWithError: NSError(domain: "test", code: 1))
        #expect(f.services.paused)
        #expect(f.controller.policy.phase == .error)
        #expect(f.controller.busy)
    }
    @Test func missingCloseAcknowledgementBlocksReconnectionAndServiceRestore() throws {
        let f = try AdapterFixture()
        f.controller.pause()
        f.clock.time += 30
        f.controller.checkDeadline()
        #expect(f.services.paused)
        #expect(f.controller.policy.phase == .error)
        #expect(f.controller.busy)
        f.controller.start()
        #expect(f.controller.policy.phase == .error)
    }
    @Test func bothConnectionEntriesRequireTheSameConsent() {
        var consent = false
        var prompts = 0
        var effects: [String] = []
        let declined = ConnectionActions(hasConsent: { consent }, requestConsent: { prompts += 1; return false },
            rememberConsent: { consent = true }, connect: { effects.append("connect") }, recover: { effects.append("recover") })
        declined.connect(); declined.recover()
        #expect(effects.isEmpty)
        #expect(!consent)
        #expect(prompts == 2)
        let approved = ConnectionActions(hasConsent: { consent }, requestConsent: { prompts += 1; return true },
            rememberConsent: { consent = true }, connect: { effects.append("connect") }, recover: { effects.append("recover") })
        approved.recover(); approved.connect()
        #expect(effects == ["recover", "connect"])
        #expect(consent)
        #expect(prompts == 3)
    }
}
