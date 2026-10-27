import Foundation
import Testing
@testable import EpsonDirectScan

@Suite @MainActor struct HelperProcessTests {
    @Test func readyIsDeliveredWhileTheReceiverIsStillRunning() async throws {
        let acknowledgement = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: acknowledgement) }
        let script = "printf '%s\\n' '{\"event\":\"ready\",\"value\":1}'; i=0; while [ ! -f \"$1\" ] && [ \"$i\" -lt 100 ]; do i=$((i+1)); /bin/sleep .01; done; test -f \"$1\""
        let helper = NativeProcess(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script, "receiver", acknowledgement.path])
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            helper.onEvent = { event in
                if event.event == "ready" { FileManager.default.createFile(atPath: acknowledgement.path, contents: Data()) }
            }
            helper.onExit = { continuation.resume(returning: $0) }
            do { try helper.start() } catch { continuation.resume(throwing: error) }
        }
        #expect(status == 0)
    }
    private func run(_ text: String) async throws -> [HelperEvent] {
        let helper = NativeProcess(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", text])
        var events: [HelperEvent] = []
        return try await withCheckedThrowingContinuation { continuation in
            helper.onEvent = { events.append($0) }
            helper.onExit = { _ in continuation.resume(returning: events) }
            do { try helper.start() } catch { continuation.resume(throwing: error) }
        }
    }
    @Test func pipeEventsAreDeliveredBeforeTheProcessExit() async throws {
        let events = try await run("{\"event\":\"button\",\"value\":1}\n{\"event\":\"closed\",\"value\":0}\n")
        #expect(events.map(\.event) == ["button", "closed"])
    }
    @Test func incompleteOrOversizedFramesCannotAuthorizeAScan() async throws {
        let truncated = try await run("{\"event\":\"button\",\"value\":1}")
        #expect(truncated.map(\.event) == ["error"])
        let oversized = try await run(String(repeating: "x", count: 5000) + "\n{\"event\":\"button\",\"value\":1}\n")
        #expect(oversized.map(\.event) == ["error"])
    }
}
