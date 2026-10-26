import Foundation
import Darwin

public struct CommandResult {
    public let status: Int32
    public let output: String
}
public enum CommandFailure: Error { case timedOut, excessiveOutput }

public func runBoundedProcess(executable: String, arguments: [String], timeout: TimeInterval = 5) throws -> CommandResult {
    let fm = FileManager.default
    let temporary = fm.temporaryDirectory.appendingPathComponent("directscan-command-" + UUID().uuidString)
    guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
    defer { try? fm.removeItem(at: temporary) }
    let handle = try FileHandle(forWritingTo: temporary)
    defer { try? handle.close() }
    let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    process.standardOutput = handle; process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    if finished.wait(timeout: .now() + max(0.01, timeout)) == .timedOut {
        process.terminate()
        if finished.wait(timeout: .now() + 0.5) == .timedOut {
            _ = kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1)
        }
        throw CommandFailure.timedOut
    }
    try handle.synchronize(); try handle.close()
    let size = (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.intValue ?? 0
    guard size <= 1_000_000 else { throw CommandFailure.excessiveOutput }
    return CommandResult(status: process.terminationStatus, output: String(decoding: try Data(contentsOf: temporary), as: UTF8.self))
}
