import Foundation
import Testing
@testable import EpsonDirectScan

@Suite @MainActor struct LeaseTests {
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
