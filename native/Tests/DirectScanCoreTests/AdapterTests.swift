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
    var cancelRequests = 0
    let feeder = EmptyFeeder()
    override var name: String? { "EPSON ES-C320W" }
    override var transportType: String? { "ICTransportTypeUSB" }
    override var hasOpenSession: Bool { openSession }
    override var selectedFunctionalUnit: ICScannerFunctionalUnit { feeder }
    override func requestOpenSession() {}
    override func requestCloseSession() { closeRequested = true }
    override func requestScan() { scanRequested = true }
    override func cancelScan() { cancelRequests += 1 }
}
private final class EmptyFeeder: ICScannerFunctionalUnitDocumentFeeder {
    var loaded = false
    var dpi: Int = 300
    var color: ICScannerPixelDataType = .RGB
    var duplex = false
    override var documentLoaded: Bool { loaded }
    override var supportedResolutions: IndexSet { IndexSet(integer: 300) }
    override var supportedBitDepths: IndexSet { IndexSet(integer: 8) }
    override var supportsDuplexScanning: Bool { true }
    override var resolution: Int { get { dpi } set { dpi = newValue } }
    override var pixelDataType: ICScannerPixelDataType { get { color } set { color = newValue } }
    override var duplexScanningEnabled: Bool { get { duplex } set { duplex = newValue } }
}
private final class DuplexFeeder: ICScannerFunctionalUnitDocumentFeeder {
    var supported = true
    var reject = false
    var enabled = false
    override var supportsDuplexScanning: Bool { supported }
    override var duplexScanningEnabled: Bool {
        get { enabled }
        set { if !reject { enabled = newValue } }
    }
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
    let storage: ScanStorage
    init(loaded: Bool = false, duplex: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storage = try ScanStorage(root: root.appendingPathComponent("private"))
        let out = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let browser = self.browser, services = self.services, clock = self.clock
        browser.device.feeder.loaded = loaded
        var snapshot = ScanSettings(destination: out.path)
        snapshot.duplex = duplex; snapshot.crop = false; snapshot.deskew = false; snapshot.rotate = false
        controller = ScannerController(storage: storage, diagnostics: Diagnostics(root: storage.root),
            settings: { snapshot }, services: services,
            makeBrowser: { browser }, conflictingApps: { false }, now: { clock.time })
        controller.start()
        controller.deviceBrowser(browser, didAdd: browser.device, moreComing: false)
        browser.device.openSession = true
        controller.device(browser.device, didOpenSessionWithError: nil)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}
@Suite @MainActor struct AdapterTests {
    @Test func actualScannerFaultAfterWatchdogIsNotSuppressed() throws {
        let f = try AdapterFixture(loaded: true)
        var completed: Int?
        f.controller.onScanFinished = { completed = $0 }
        f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
        f.controller.scanAuthorized()
        f.clock.time = 15; f.controller.checkDeadline()
        f.controller.device(f.browser.device, didEncounterError: NSError(domain: ICErrorDomain, code: -9933))
        f.controller.scannerDevice(f.browser.device, didCompleteScanWithError: nil)
        #expect(completed == nil && f.controller.policy.phase == .error)
        #expect(try f.storage.hasUnfinishedJobs())
    }
    // These drive the real controller/storage; only the physical ICA device is replaced.
    @Test func emptyCompletionIsRemovedOnlyAfterConfirmedClose() throws {
        let f = try AdapterFixture(loaded: true)
        var completed: Int?
        f.controller.onScanFinished = { completed = $0 }
        f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
        f.controller.scanAuthorized()
        #expect(f.browser.device.scanRequested)
        f.controller.scannerDevice(f.browser.device, didCompleteScanWithError: nil)
        #expect(completed == 0)
        #expect(f.controller.policy.phase != .error)
        #expect(try f.storage.hasUnfinishedJobs())
        f.controller.pause()
        #expect(try f.storage.hasUnfinishedJobs())
        f.browser.device.openSession = false
        f.controller.device(f.browser.device, didCloseSessionWithError: nil)
        #expect(try !f.storage.hasUnfinishedJobs())
        #expect(f.controller.sessionReleased)
    }
    @Test func documentedCancellationIsNeutralOnlyInICDomain() throws {
        for domain in [ICErrorDomain, "unrelated.transport"] {
            let f = try AdapterFixture(loaded: true)
            var completed: Int?
            f.controller.onScanFinished = { completed = $0 }
            f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
            f.controller.scanAuthorized()
            f.controller.scannerDevice(f.browser.device, didCompleteScanWithError: NSError(domain: domain, code: -9924))
            #expect(domain == ICErrorDomain ? completed == 0 : completed == nil)
            #expect((f.controller.policy.phase == .error) == (domain != ICErrorDomain))
            f.controller.pause(); f.browser.device.openSession = false
            f.controller.device(f.browser.device, didCloseSessionWithError: nil)
        }
    }
    @Test func emptyCompletionNeverDiscardsUnknownPartialFileOrFailedClose() throws {
        for partial in [true, false] {
            let f = try AdapterFixture(loaded: true)
            f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
            f.controller.scanAuthorized()
            let job = try #require(f.storage.pendingJobs().first)
            let source = job.directory.appendingPathComponent("unfinished.jpg")
            if partial { try Data([0xff, 0xd8, 0x01]).write(to: source) }
            f.controller.scannerDevice(f.browser.device, didCompleteScanWithError: nil)
            f.controller.pause(); f.browser.device.openSession = false
            f.controller.device(f.browser.device, didCloseSessionWithError: partial ? nil : NSError(domain: "close", code: 1))
            #expect(f.controller.policy.phase == .error)
            #expect(try f.storage.hasUnfinishedJobs())
            if partial { #expect(try Data(contentsOf: source) == Data([0xff, 0xd8, 0x01])) }
        }
    }
    @Test func noProgressCancelsOnceThenWaitsForCompletionAndClose() throws {
        let f = try AdapterFixture(loaded: true)
        var completed: Int?
        f.controller.onScanFinished = { completed = $0 }
        f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
        f.controller.scanAuthorized()
        f.clock.time = 14; f.controller.checkDeadline()
        #expect(f.browser.device.cancelRequests == 0)
        f.clock.time = 15; f.controller.checkDeadline()
        #expect(f.browser.device.cancelRequests == 1)
        #expect(!f.browser.device.closeRequested && completed == nil)
        f.clock.time = 16; f.controller.checkDeadline()
        #expect(f.browser.device.cancelRequests == 1)
        f.controller.scannerDevice(f.browser.device, didCompleteScanWithError: NSError(domain: ICErrorDomain, code: -9924))
        #expect(completed == 0 && f.controller.policy.phase != .error)
        f.controller.pause(); f.browser.device.openSession = false
        f.controller.device(f.browser.device, didCloseSessionWithError: nil)
        #expect(try !f.storage.hasUnfinishedJobs())
    }
    @Test func progressingPagesResetGuardAndPartialDuplexStopRetainsSource() throws {
        let f = try AdapterFixture(loaded: true, duplex: true), image = try StorageTests()
        f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
        f.controller.scanAuthorized()
        let job = try #require(f.storage.pendingJobs().first)
        let source = job.directory.appendingPathComponent("front.jpg"); try image.jpeg(source)
        f.clock.time = 10; f.controller.scannerDevice(f.browser.device, didScanTo: source)
        f.clock.time = 20; f.controller.checkDeadline()
        #expect(f.browser.device.cancelRequests == 0)
        f.clock.time = 25; f.controller.checkDeadline()
        #expect(f.browser.device.cancelRequests == 1)
        f.controller.scannerDevice(f.browser.device, didCompleteScanWithError: nil)
        #expect(f.controller.policy.phase == .error)
        #expect(try f.storage.manifest(job: job).pages.count == 1)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
    @Test func missingCancellationCompletionRemainsAnErrorWithRetainedJob() throws {
        let f = try AdapterFixture(loaded: true)
        f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
        f.controller.scanAuthorized()
        f.clock.time = 15; f.controller.checkDeadline()
        f.clock.time = 27; f.controller.checkDeadline()
        #expect(f.controller.policy.phase == .error)
        #expect(try f.storage.hasUnfinishedJobs())
    }
    @Test func cancellationNotificationCannotExtendAcknowledgementOrPublishPartialJob() throws {
        for withPage in [true, false] {
            let f = try AdapterFixture(loaded: true), image = try StorageTests()
            f.controller.scannerDevice(f.browser.device, didSelect: f.browser.device.feeder, error: nil)
            f.controller.scanAuthorized()
            let job = try #require(f.storage.pendingJobs().first)
            if withPage {
                let source = job.directory.appendingPathComponent("page.jpg"); try image.jpeg(source)
                f.controller.scannerDevice(f.browser.device, didScanTo: source)
            }
            let cancelled = NSError(domain: ICErrorDomain, code: -9924)
            f.controller.device(f.browser.device, didEncounterError: cancelled)
            if withPage {
                f.controller.scannerDevice(f.browser.device, didCompleteScanWithError: nil)
            } else {
                f.clock.time = 8
                f.controller.device(f.browser.device, didEncounterError: cancelled)
                f.clock.time = 12; f.controller.checkDeadline()
            }
            #expect(f.controller.policy.phase == .error)
            #expect(try f.storage.hasUnfinishedJobs())
            #expect(try FileManager.default.contentsOfDirectory(atPath: job.destination.path).isEmpty)
        }
    }
    @Test func duplexRequiresSupportAndMatchingReadback() throws {
        let feeder = DuplexFeeder()
        try ScannerController.configureDuplex(feeder, enabled: true)
        #expect(feeder.enabled)
        try ScannerController.configureDuplex(feeder, enabled: false)
        #expect(!feeder.enabled)
        feeder.supported = false
        #expect(throws: (any Error).self) { try ScannerController.configureDuplex(feeder, enabled: true) }
        feeder.supported = true; feeder.reject = true
        #expect(throws: (any Error).self) { try ScannerController.configureDuplex(feeder, enabled: true) }
    }
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
