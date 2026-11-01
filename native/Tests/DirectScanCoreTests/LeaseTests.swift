import Foundation
import Testing
import Darwin
import DirectScanCore
@testable import EpsonDirectScan

@Suite @MainActor struct LeaseTests {
    @Test func releasedOwnerUnlocksEvenIfAnUnrelatedSpawnTemporarilyInheritedItsDescriptor() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        var lease:ScannerLease?=try ScannerLease(root:root)
        #expect(lease != nil)
        var ready=[Int32](repeating:0,count:2),finish=[Int32](repeating:0,count:2)
        guard pipe(&ready)==0,pipe(&finish)==0 else{throw POSIXError(.EIO)}
        for fd in ready+finish {_=fcntl(fd,F_SETFD,FD_CLOEXEC)}
        _=fcntl(finish[1],F_SETNOSIGPIPE,1)
        // Pause an unrelated child before exec, where close-on-exec has not
        // closed inherited file descriptions yet. The child uses only C I/O.
        let library=try #require(dlopen(nil,RTLD_LAZY));defer{dlclose(library)}
        let symbol=try #require(dlsym(library,"fork"))
        let child=unsafeBitCast(symbol,to:(@convention(c)()->pid_t).self)()
        guard child>=0 else{throw POSIXError(.EAGAIN)}
        if child==0 {
            _=Darwin.close(ready[0]);_=Darwin.close(finish[1])
            var byte:UInt8=1;_=Darwin.write(ready[1],&byte,1);_=Darwin.read(finish[0],&byte,1)
            Darwin._exit(0)
        }
        _=Darwin.close(ready[1]);_=Darwin.close(finish[0])
        defer {
            var byte:UInt8=1;_=Darwin.write(finish[1],&byte,1);_=Darwin.close(finish[1]);_=Darwin.close(ready[0])
            var status:Int32=0
            let deadline=Date(timeIntervalSinceNow:1)
            while Darwin.waitpid(child,&status,WNOHANG)==0 && Date()<deadline {Thread.sleep(forTimeInterval:0.01)}
            if Darwin.waitpid(child,&status,WNOHANG)==0 {_=Darwin.kill(child,SIGKILL);_=Darwin.waitpid(child,&status,0)}
        }
        var byte:UInt8=0
        var available=pollfd(fd:ready[0],events:Int16(POLLIN),revents:0)
        guard Darwin.poll(&available,1,3000)>0 else {throw CocoaError(.fileReadUnknown)}
        #expect(Darwin.read(ready[0],&byte,1)==1)
        lease=nil
        var next:ScannerLease?
        do {next=try ScannerLease(root:root)} catch {Issue.record("Released owner left an inherited lock: \(error)")}
        withExtendedLifetime(next){}
    }
    @Test func survivingChildBlocksRestartRestorationUntilItsLeaseIsReleased() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let memo = root.appendingPathComponent("epson-services.json")
        try Data("[]".utf8).write(to: memo) // No real launch agents may be touched.
        let ready = root.appendingPathComponent("ready"), release = root.appendingPathComponent("release")
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.arguments = ["python3", "-c", "import fcntl,pathlib,sys,time\nf=open(sys.argv[1],'a')\nfcntl.flock(f,fcntl.LOCK_EX)\npathlib.Path(sys.argv[2]).touch()\nwhile not pathlib.Path(sys.argv[3]).exists(): time.sleep(.01)",
            root.appendingPathComponent("scanner.lock").path, ready.path, release.path]
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run()
        defer {
            if child.isRunning { child.terminate(); child.waitUntilExit() }
            try? FileManager.default.removeItem(at: root)
        }
        let deadline = Date(timeIntervalSinceNow: 3)
        while !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        #expect(FileManager.default.fileExists(atPath: ready.path))
        let mode = EpsonButtonMode(root: root, diagnostics: Diagnostics(root: root))
        #expect(throws: (any Error).self) { try mode.restore() }
        #expect(FileManager.default.fileExists(atPath: memo.path))
        try Data().write(to: release); child.waitUntilExit()
        try mode.restore()
        #expect(!FileManager.default.fileExists(atPath: memo.path))
    }
}
