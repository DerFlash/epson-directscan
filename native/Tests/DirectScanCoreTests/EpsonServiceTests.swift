import Foundation
import Testing
import DirectScanCore
@testable import EpsonDirectScan

private final class ServiceCommands {
    let labels:Set<String>=["com.epson.eventmanager.agent","com.epson.scannermonitor"]
    var loaded:Set<String>=["com.epson.eventmanager.agent","com.epson.scannermonitor"]
    var calls:[[String]]=[]
    var failBootout:String?
    func run(_ args:[String],_ output:Bool)throws->(Int32,String) {
        calls.append(args)
        if args.first=="/bin/ps" {return (0,"")}
        guard args.count>=3,args.first=="/bin/launchctl" else{throw CocoaError(.fileReadCorruptFile)}
        switch args[1] {
        case "print":return (loaded.contains(String(args[2].split(separator:"/").last!)) ? 0:113,"")
        case "bootout":
            let label=String(args[2].split(separator:"/").last!)
            if label==failBootout {return (1,"")};loaded.remove(label);return (0,"")
        case "bootstrap":loaded.insert(URL(fileURLWithPath:args.last!).deletingPathExtension().lastPathComponent);return (0,"")
        default:throw CocoaError(.fileReadCorruptFile)
        }
    }
}
@Suite struct EpsonServiceTests {
    private func folder()throws->URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);return root
    }
    @Test func reacquireDoesNotRestartEpsonAgentsAndPreservesOriginalRestoreState() throws {
        let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
        let shell=ServiceCommands(),mode=EpsonButtonMode(root:root,diagnostics:Diagnostics(root:root),runCommand:shell.run)
        try mode.acquire();let memo=root.appendingPathComponent("epson-services.json"),original=try Data(contentsOf:memo)
        let count=shell.calls.count
        // Simulate a vendor helper returning after a scanner reconnect/login.
        shell.loaded.insert("com.epson.scannermonitor")
        try mode.acquire()
        #expect(shell.loaded.isEmpty)
        #expect(!shell.calls.dropFirst(count).contains{$0.count>1 && $0[1]=="bootstrap"})
        #expect(try Data(contentsOf:memo)==original)
        try mode.restore();#expect(shell.loaded==shell.labels)
        #expect(!FileManager.default.fileExists(atPath:memo.path))
    }
    @Test func activeScannerLeaseBlocksTakeoverBeforeAnyServiceChange() throws {
        let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
        let shell=ServiceCommands(),mode=EpsonButtonMode(root:root,diagnostics:Diagnostics(root:root),runCommand:shell.run)
        let lease=try ScannerLease(root:root)
        withExtendedLifetime(lease){#expect(throws:(any Error).self){try mode.acquire()}}
        #expect(shell.calls.isEmpty && shell.loaded==shell.labels)
    }
    @Test func failedInitialTakeoverRestoresOnlyOriginallyRunningAgents() throws {
        let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
        let shell=ServiceCommands();shell.failBootout="com.epson.scannermonitor"
        let mode=EpsonButtonMode(root:root,diagnostics:Diagnostics(root:root),runCommand:shell.run)
        #expect(throws:(any Error).self){try mode.acquire()}
        #expect(shell.loaded==shell.labels)
        #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("epson-services.json").path))
    }
    @Test @MainActor func activeRestartWithMissingDestinationRetainsMemoAndStopsReturnedAgents() throws {
        let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
        let storage=try ScanStorage(root:root),shell=ServiceCommands()
        let mode=EpsonButtonMode(root:root,diagnostics:Diagnostics(root:root),runCommand:shell.run)
        try mode.acquire()
        let memo=root.appendingPathComponent("epson-services.json"),original=try Data(contentsOf:memo)
        shell.loaded.insert("com.epson.scannermonitor")
        let settings=ScanSettings(destination:root.appendingPathComponent("unavailable").path)
        let fresh=EpsonButtonMode(root:root,diagnostics:Diagnostics(root:root),runCommand:shell.run)
        let controller=ScanCoordinator(storage:storage,diagnostics:Diagnostics(root:root),settings:{settings},services:fresh,
            makeHelper:{_ in Issue.record("Missing destination must never launch a scanner helper");throw CocoaError(.featureUnsupported)},conflictingApps:{false})
        controller.start()
        #expect(controller.policy.phase == .error && controller.ownsEpsonButtons)
        #expect(shell.loaded.isEmpty && FileManager.default.fileExists(atPath:memo.path))
        #expect(try Data(contentsOf:memo)==original)
        controller.pause()
        #expect(shell.loaded==shell.labels && !controller.ownsEpsonButtons)
    }
}
