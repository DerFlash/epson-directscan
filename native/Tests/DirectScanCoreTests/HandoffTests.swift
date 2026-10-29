import Foundation
import Testing
@testable import DirectScanCore
@testable import EpsonDirectScan

private final class HandoffServices: EpsonServices {
    var paused = false
    var restoreCalls = 0
    func acquire() throws { paused = true }
    func restore() throws { paused = false;restoreCalls += 1 }
}
private final class FakeHelper: NativeHelper {
    var onEvent: ((HelperEvent) -> Void)?
    var onExit: ((Int32) -> Void)?
    var cancelled = false
    var finishRequested = false
    var armRequested = false
    func start() throws {}
    func cancel() { cancelled = true }
    func forceStop() { cancelled = true }
    func finish() { finishRequested = true }
    func arm() { armRequested = true }
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
    func profileExport() throws -> (ScanJob,FakeHelper) {
        settings.value.automaticFeeding=true
        let p=ScanProfile(name:"Karte");settings.value.profiles=[p];settings.value.activeProfileID=p.id
        trigger()
        guard case .feeding(let job) = factory.roles.last else {throw ScanFailure.invalidSettings}
        let image=try StorageTests(), feed=factory.helpers[1];feed.emit("ready",1)
        try image.jpeg(job.directory.appendingPathComponent("a.jpg"),width:80,height:40)
        feed.onEvent?(HelperEvent(event:"page",value:1,file:"a.jpg",sheet:1,side:0))
        feed.emit("end",0);feed.emit("closed",0);feed.exit()
        guard case .export = factory.roles.last,let worker=factory.helpers.last else {throw ScanFailure.invalidSettings}
        return (job,worker)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}
@Suite @MainActor struct HandoffTests {
    @Test func errorAndRecoveryKeepEpsonButtonsUntilExplicitPause() throws {
        let f=try HandoffFixture(),p=try transparentProfile()
        f.settings.value.profiles=[p];f.settings.value.activeProfileID=p.id;f.trigger()
        let capture=f.factory.helpers[1];capture.emit("ready",1)
        capture.emit("error",394);capture.emit("closed",0);capture.exit(1)
        #expect(f.services.paused && f.services.restoreCalls==0 && f.controller.ownsEpsonButtons)
        #expect(!f.controller.listening && f.controller.policy.phase == .error)
        #expect(try f.storage.hasUnfinishedJobs())
        f.controller.recover()
        #expect(f.services.paused && f.services.restoreCalls==0 && f.controller.ownsEpsonButtons)
        #expect(try !f.storage.hasUnfinishedJobs())
        #expect(f.factory.roles.count==3 && f.factory.roles.last == .button)
        let receiver=f.factory.helpers.last!;receiver.emit("ready",1)
        f.controller.pause();receiver.emit("closed",0);receiver.exit()
        #expect(!f.services.paused && f.services.restoreCalls==1 && !f.controller.ownsEpsonButtons)
    }
    @Test func pendingJobBlocksTransportButKeepsRequestedButtonOwnership() throws {
        let f=try HandoffFixture();f.button.emit("ready",1)
        f.controller.pause();f.button.emit("closed",0);f.button.exit()
        _=try f.storage.beginJob(settings:f.settings.value)
        f.controller.start()
        #expect(f.controller.policy.phase == .error && f.services.paused && f.controller.ownsEpsonButtons)
        #expect(f.factory.roles.count==1)
    }
    @Test func internalSleepOrSettingsPauseKeepsVendorsStoppedAcrossResume() throws {
        let f=try HandoffFixture();f.button.emit("ready",1)
        f.controller.pause(releaseEpsonServices:false)
        f.button.emit("closed",0);f.button.exit()
        #expect(f.services.paused && f.services.restoreCalls==0)
        #expect(f.controller.ownsEpsonButtons && f.controller.sessionReleased)
        f.controller.start()
        #expect(f.services.paused && f.services.restoreCalls==0 && f.factory.roles.last == .button)
    }
    @Test func internalPauseCannotRevokeAnExplicitReleaseWaitingForClose() throws {
        let f=try HandoffFixture();f.button.emit("ready",1)
        f.controller.pause()
        f.controller.pause(releaseEpsonServices:false)
        #expect(f.services.paused)
        f.button.emit("closed",0);f.button.exit()
        #expect(!f.services.paused && f.services.restoreCalls==1)
        #expect(!f.controller.ownsEpsonButtons && f.controller.sessionReleased && !f.controller.listening)
    }
    @Test func transparentSingleCardUsesNativeHelperButKeepsIndividualJPGOrCardPDF() throws {
        for format in [OutputFormat.jpg,.pdf] {
            let f=try HandoffFixture(),image=try StorageTests(),p=try transparentProfile()
            f.settings.value.profiles=[p];f.settings.value.activeProfileID=p.id
            f.settings.value.duplex=true;f.settings.value.outputFormat=format
            f.trigger()
            guard case .feeding(let job)=f.factory.roles.last else {Issue.record("Transparent single card must use native capture");return}
            #expect(!f.controller.collecting && !job.settings.automaticFeeding)
            let capture=f.factory.helpers[1];capture.emit("ready",1);capture.emit("batchBegin",1)
            for i in 1...2 {
                let name="holder-\(i).jpg";try image.jpeg(job.directory.appendingPathComponent(name),width:500,height:800)
                capture.onEvent?(HelperEvent(event:"page",value:i,file:name,sheet:1,side:i-1))
            }
            capture.emit("batchEnd",1);capture.emit("end",0);capture.emit("closed",0)
            #expect(f.factory.roles.count==2)
            capture.exit()
            #expect(try f.storage.manifest(job:job).endReason == .completed)
            guard case .export=f.factory.roles.last else {Issue.record("Missing export worker");return}
            let exporter=try #require(f.factory.helpers.last)
            let status=ExportWorkerMain.run(["app","--export-worker",f.storage.root.path,job.id.uuidString,String(getppid())],emit:{exporter.onEvent?($0)})
            #expect(status==0);exporter.exit()
            let outputs=try FileManager.default.contentsOfDirectory(atPath:job.destination.path)
            #expect(outputs.count == (format == .jpg ? 2:1))
            #expect(outputs.allSatisfy{$0.hasSuffix(format == .jpg ? ".jpg":".pdf") && !$0.contains("Sammlung")})
            #expect(f.controller.imagesSaved==2 && !f.controller.collecting)
            #expect(try !f.storage.hasUnfinishedJobs() && f.factory.roles.last == .button)
        }
    }
    @Test func transparentSingleCardStallIsBoundedEvenThoughItIsNotACollection() throws {
        let f=try HandoffFixture(),p=try transparentProfile()
        f.settings.value.profiles=[p];f.settings.value.activeProfileID=p.id;f.trigger()
        guard case .feeding=f.factory.roles.last else {Issue.record("Expected native capture");return}
        let capture=f.factory.helpers[1];capture.emit("ready",1);capture.emit("batchBegin",1)
        #expect(!f.controller.collecting)
        f.clock.time=14;f.controller.checkDeadline();#expect(!capture.finishRequested)
        f.clock.time=15;f.controller.checkDeadline();#expect(capture.finishRequested && !capture.cancelled)
        capture.emit("batchEnd",1);capture.emit("end",0);capture.emit("closed",0);capture.exit()
        f.factory.helpers.last?.emit("ready",1)
        #expect(f.controller.policy.phase == .ready && f.controller.imagesSaved==0)
        #expect(try !f.storage.hasUnfinishedJobs())
        #expect(f.controller.message.contains("Einzug"))
    }
    @Test func parentLossDuringFinalExportCannotPublishOrRemoveOriginals() throws {
        let f=try HandoffFixture();let (job,_)=try f.profileExport()
        var alive=true,clock:Double=0,exportChecks=0
        let status=ExportWorkerMain.run(["app","--export-worker",f.storage.root.path,job.id.uuidString,String(getppid())],emit:{event in
            if event.event == "checkpoint",event.value == 2 {exportChecks += 1;if exportChecks == 3 {alive=false}}
        },parentAlive:{alive},now:{clock += 2;return clock})
        #expect(status == 1 && exportChecks == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath:job.destination.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath:job.directory.appendingPathComponent("a.jpg").path))
        #expect(try f.storage.hasUnfinishedJobs())
    }
    @Test func parentLossDuringFinalizationKeepsOriginalsAndPublishedReceiptForRecovery() throws {
        let f=try HandoffFixture();let (job,_)=try f.profileExport()
        var alive=true,clock:Double=0,finishChecks=0
        let status=ExportWorkerMain.run(["app","--export-worker",f.storage.root.path,job.id.uuidString,String(getppid())],emit:{event in
            if event.event == "checkpoint",event.value == 3 {finishChecks += 1;if finishChecks == 3 {alive=false}}
        },parentAlive:{alive},now:{clock += 2;return clock})
        #expect(status == 1 && finishChecks == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath:job.destination.path).count == 1)
        #expect(FileManager.default.fileExists(atPath:job.directory.appendingPathComponent("a.jpg").path))
        #expect(try f.storage.hasUnfinishedJobs())
        #expect(try f.storage.export(job:job).count == 1)
        try f.storage.finish(job:job)
    }
    @Test func healthyExportTailLivesBeyondTwentySecondsAndStallsRemainBounded() throws {
        let f=try HandoffFixture();let (_,worker)=try f.profileExport()
        worker.emit("processing",1)
        f.clock.time=21;f.controller.checkDeadline()
        #expect(!worker.cancelled && f.controller.policy.phase == .scanning)
        f.clock.time=100;worker.emit("checkpoint",2)
        f.clock.time=221;f.controller.checkDeadline()
        #expect(!worker.cancelled && f.controller.busy)
        f.clock.time=241;f.controller.checkDeadline()
        #expect(worker.cancelled && f.controller.policy.phase == .error)
    }
    @Test func cancellingExportAfterScannerReleaseDoesNotInventADeviceReleaseFailure() throws {
        let f = try HandoffFixture(), image = try StorageTests()
        f.settings.value.automaticFeeding=true
        let p=ScanProfile(name:"Karte");f.settings.value.profiles=[p];f.settings.value.activeProfileID=p.id
        f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else {Issue.record("Expected feeding");return}
        let feed=f.factory.helpers[1];feed.emit("ready",1)
        try image.jpeg(job.directory.appendingPathComponent("a.jpg"))
        feed.onEvent?(HelperEvent(event:"page",value:1,file:"a.jpg",sheet:1,side:0))
        feed.emit("end",0);feed.emit("closed",0);feed.exit()
        guard case .export = f.factory.roles.last else {Issue.record("Expected export");return}
        let exporter=try #require(f.factory.helpers.last)
        f.controller.pause();#expect(exporter.cancelled)
        exporter.exit(15) // SIGTERM needs no device close: feeding already confirmed it.
        #expect(f.controller.policy.phase == .paused && !f.controller.busy && f.controller.sessionReleased)
        #expect(!f.services.paused && !f.controller.listening)
        let pending = try f.storage.hasUnfinishedJobs()
        #expect(f.factory.roles.count == 3 && pending)
    }
    @Test func profileCollectionProcessesOnlyAfterScannerCloseAndPreservesReadyNotice() throws {
        let f = try HandoffFixture(), image = try StorageTests()
        f.settings.value.automaticFeeding = true;f.settings.value.duplex = true
        var profile = ScanProfile(name:"Karte");profile.orientation = .vision;profile.frontRotation = 90;profile.backRotation = 270
        f.settings.value.profiles = [profile];f.settings.value.activeProfileID = profile.id
        f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else { Issue.record("Expected feeding");return }
        let worker = f.factory.helpers[1];worker.emit("ready",1);worker.emit("batchBegin",1)
        for i in 1...2 {let name = "\(i).jpg";try image.jpeg(job.directory.appendingPathComponent(name),width:80,height:40);worker.onEvent?(HelperEvent(event:"page",value:i,file:name,sheet:1,side:i-1))}
        worker.emit("batchEnd",1);worker.emit("end",0);worker.emit("closed",0)
        #expect(f.factory.roles.count == 2)
        worker.exit()
        guard case .export = f.factory.roles.last else { Issue.record("Missing isolated export worker");return }
        #expect(f.controller.busy)
        #expect(try FileManager.default.contentsOfDirectory(atPath:job.destination.path).isEmpty)
        let exporter = try #require(f.factory.helpers.last)
        let result = ExportWorkerMain.run(["app","--export-worker",f.storage.root.path,job.id.uuidString,String(getppid())],emit:{ exporter.onEvent?($0) })
        #expect(result == 0)
        exporter.exit()
        #expect(try !f.storage.hasUnfinishedJobs())
        #expect(f.factory.roles.last == .button && f.controller.lastFile?.pathExtension == "pdf")
        f.factory.helpers.last?.emit("ready",1)
        #expect(f.controller.message.contains("feste Ausrichtung"))
    }
    @Test func invalidExportProgressAndCancelCannotPublishOrRestart() throws {
        let f = try HandoffFixture(), image = try StorageTests()
        f.settings.value.automaticFeeding = true
        let profile = ScanProfile(name:"Karte");f.settings.value.profiles = [profile];f.settings.value.activeProfileID = profile.id
        f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else { Issue.record("Expected feeding");return }
        let worker = f.factory.helpers[1];worker.emit("ready",1)
        try image.jpeg(job.directory.appendingPathComponent("a.jpg"))
        worker.onEvent?(HelperEvent(event:"page",value:1,file:"a.jpg",sheet:1,side:0))
        worker.emit("end",0);worker.emit("closed",0);worker.exit()
        guard case .export = f.factory.roles.last else { Issue.record("Missing export worker");return }
        let exporter = try #require(f.factory.helpers.last)
        exporter.emit("processing",99)
        #expect(exporter.cancelled && f.controller.policy.phase == .error)
        exporter.emit("closed",0);exporter.exit(1)
        #expect(f.factory.roles.count == 3 && !f.controller.listening)
        #expect(try f.storage.hasUnfinishedJobs())
        #expect(try FileManager.default.contentsOfDirectory(atPath:job.destination.path).isEmpty)
    }
    @Test func scannerFaultRemainsVisibleWithPaperPathAndRecoveryHint() throws {
        let f = try HandoffFixture(); f.trigger()
        _ = try f.storage.beginJob(settings: f.settings.value)
        let worker = f.factory.helpers[1]
        worker.emit("error", -206); worker.emit("closed", 0); worker.exit(1)
        #expect(f.controller.policy.phase == .error && !f.controller.listening)
        #expect(f.controller.message.contains("Papierweg"))
        #expect(f.controller.message.contains("neu verbinden"))
        #expect(try f.storage.hasUnfinishedJobs())
        #expect(f.factory.roles.count == 2)
    }
    @Test func disconnectedReceiverExplainsExplicitReconnectAndDoesNotReplay() throws {
        let f = try HandoffFixture(); f.button.emit("ready", 1)
        f.button.emit("error", -106); f.button.emit("closed", 0); f.button.exit(1)
        #expect(f.controller.policy.phase == .error && !f.controller.listening)
        #expect(f.controller.message.contains("getrennt"))
        #expect(f.controller.message.contains("neu verbinden"))
        #expect(f.factory.roles.count == 1 && f.services.paused)
        #expect(f.controller.buttonEvents == 0)
    }
    @Test func emptyScanNoticeSurvivesRearmAndNeedsCloseAndExit() throws {
        let f = try HandoffFixture(); f.trigger()
        let worker = f.factory.helpers[1]
        worker.emit("empty", 2) // no progress
        #expect(f.factory.roles.count == 2)
        worker.emit("closed", 0); #expect(f.factory.roles.count == 2)
        worker.exit()
        #expect(f.factory.roles.count == 3)
        f.factory.helpers[2].emit("ready", 1)
        #expect(f.controller.policy.phase == .ready && f.controller.listening)
        #expect(f.controller.message.contains("Einzug") && f.controller.message.contains("prüfen"))
        #expect(f.controller.imagesSaved == 0)
    }
    @Test func invalidEmptyReasonOrExitCannotRearm() throws {
        for (reason, exit) in [(99, Int32(0)), (2, Int32(1))] {
            let f = try HandoffFixture(); f.trigger()
            let worker = f.factory.helpers[1]; worker.emit("empty", reason)
            worker.emit("closed", 0); worker.exit(exit)
            #expect(f.controller.policy.phase == .error)
            #expect(f.factory.roles.count == 2)
        }
    }
    @Test func outputAfterEmptyCompletionCannotTurnItIntoASuccess() throws {
        let f = try HandoffFixture(); f.trigger()
        let worker = f.factory.helpers[1]
        worker.emit("empty", 1); worker.emit("file", 1, file: "unexpected.jpg")
        worker.emit("complete", 1); worker.emit("closed", 0); worker.exit()
        #expect(f.controller.policy.phase == .error)
        #expect(f.factory.roles.count == 2)
        #expect(f.controller.imagesSaved == 0)
    }
    @Test func feedingStallFinishesWithoutAffectingUnlimitedPaperWaiting() throws {
        let f = try HandoffFixture(); f.settings.value.automaticFeeding = true
        f.settings.value.feedingTimeoutSeconds = 0
        f.trigger(); let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        f.clock.time = 1000; f.controller.checkDeadline(); #expect(!worker.finishRequested)
        worker.emit("batchBegin", 1)
        f.clock.time = 1014; f.controller.checkDeadline(); #expect(!worker.finishRequested)
        f.clock.time = 1015; f.controller.checkDeadline(); #expect(worker.finishRequested && !worker.cancelled)
        worker.emit("batchEnd", 1); worker.emit("end", 0); worker.emit("closed", 0); worker.exit()
        f.factory.helpers.last?.emit("ready", 1)
        #expect(f.controller.policy.phase == .ready)
        #expect(f.controller.message.contains("Einzug"))
        #expect(try !f.storage.hasUnfinishedJobs())
    }
    @Test func feedingProgressResetsGuardAndCompletedPagesSurviveStall() throws {
        let f = try HandoffFixture(), image = try StorageTests()
        f.settings.value.automaticFeeding = true; f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else { Issue.record("Expected feeding"); return }
        let worker = f.factory.helpers[1]; worker.emit("ready", 1); worker.emit("batchBegin", 1)
        try image.jpeg(job.directory.appendingPathComponent("page.jpg"))
        f.clock.time = 10
        worker.onEvent?(HelperEvent(event: "page", value: 1, file: "page.jpg", sheet: 1, side: 0))
        f.clock.time = 20; f.controller.checkDeadline(); #expect(!worker.finishRequested)
        f.clock.time = 25; f.controller.checkDeadline(); #expect(worker.finishRequested)
        worker.emit("batchEnd", 1); worker.emit("end", 0); worker.emit("closed", 0); worker.exit()
        #expect(f.controller.lastFile?.pathExtension == "pdf")
        #expect(try !f.storage.hasUnfinishedJobs())
    }
    @Test func feedingStartsOnlyFromPhysicalButtonAndUnlimitedIdleHasNoWholeSessionDeadline() throws {
        let f = try HandoffFixture()
        f.settings.value.automaticFeeding = true; f.settings.value.feedingTimeoutSeconds = 0
        f.trigger()
        guard case .feeding(let job) = f.factory.roles.last else { Issue.record("Expected automatic feeding"); return }
        #expect(job.settings.automaticFeeding)
        let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        #expect(worker.armRequested)
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
        f.clock.time = 24; f.controller.checkDeadline()
        #expect(!worker.finishRequested && !worker.cancelled)
        f.clock.time = 25; worker.emit("batchEnd", 1)
        f.clock.time = 54; f.controller.checkDeadline(); #expect(!worker.finishRequested)
        f.clock.time = 55; f.controller.checkDeadline(); #expect(worker.finishRequested && !worker.cancelled)
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
        let original = try Data(contentsOf: job.directory.appendingPathComponent("front.jpg"))
        worker.onEvent?(HelperEvent(event: "page", value: 1, file: "front.jpg", sheet: 1, side: 0))
        worker.emit("end", 0); worker.emit("closed", 0); worker.exit()
        #expect(f.controller.lastCollectionIncomplete)
        f.factory.helpers.last?.emit("ready", 1)
        #expect(f.controller.message.contains("unvollständig"))
        #expect(f.controller.lastFile?.pathExtension == "pdf")
        let retained = f.storage.recoveryDirectory.appendingPathComponent(job.id.uuidString)
        #expect(try Data(contentsOf: retained.appendingPathComponent("front.jpg")) == original)
        #expect(FileManager.default.fileExists(atPath: retained.appendingPathComponent("job.json").path))
        #expect(try !f.storage.hasUnfinishedJobs())
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
    @Test func finishDuringStartupIsLatchedAndNeverArmsTheScanner() throws {
        let f = try HandoffFixture(); f.settings.value.automaticFeeding = true; f.trigger()
        let worker = f.factory.helpers[1]
        f.controller.finishCollection(pauseAfter: true)
        #expect(!worker.finishRequested && !worker.armRequested)
        worker.emit("ready", 1)
        #expect(worker.finishRequested && !worker.armRequested)
        worker.emit("end", 0); worker.emit("closed", 0); worker.exit()
        #expect(f.factory.roles.count == 2)
        #expect(!f.controller.listening && f.controller.sessionReleased && !f.services.paused)
        #expect(try !f.storage.hasUnfinishedJobs())
    }
    @Test func finishAcceptsAnAlreadyArmedInFlightBatchWithoutExtendingItsDeadline() throws {
        let f = try HandoffFixture(); f.settings.value.automaticFeeding = true; f.trigger()
        let worker = f.factory.helpers[1]; worker.emit("ready", 1)
        f.controller.finishCollection(); worker.emit("batchBegin", 1)
        #expect(f.controller.policy.phase == .scanning && !worker.cancelled)
        f.clock.time = 25; f.controller.checkDeadline()
        #expect(worker.cancelled)
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
        #expect(f.services.paused)
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
