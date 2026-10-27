import Foundation
import Testing
@testable import DirectScanCore

@Suite struct ProcessTests {
    @Test func systemCommandOutputAndFailureStatusAreReported() throws {
        let result = try runBoundedProcess(executable: "/usr/bin/printf", arguments: ["%s", "a folder with spaces"], timeout: 2)
        #expect(result.status == 0)
        #expect(result.output == "a folder with spaces")
        let failure = try runBoundedProcess(executable: "/usr/bin/false", arguments: [], timeout: 2)
        #expect(failure.status != 0)
    }
    @Test func hungCommandCannotBlockTheAppIndefinitely() throws {
        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: (any Error).self) {
            try runBoundedProcess(executable: "/bin/sleep", arguments: ["5"], timeout: 0.1)
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 2.5)
    }
}
