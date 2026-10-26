import Foundation
import Darwin
import DirectScanCore

// A per-login takeover of Epson's two background agents. No vendor files change.
final class EpsonButtonMode {
    private let root: URL
    private let diagnostics: Diagnostics
    private let entries = [
        "com.epson.eventmanager.agent": "/Library/LaunchAgents/com.epson.eventmanager.agent.plist",
        "com.epson.scannermonitor": "/Library/LaunchAgents/com.epson.scannermonitor.plist"]
    private let executables = [
        "/Library/Application Support/EPSON/Scanner/ScannerMonitor/Epson Scanner Monitor.app/Contents/MacOS/Epson Scanner Monitor",
        "/Applications/Epson Software/Event Manager.app/Contents/Resources/Assistants/Event Manager/EEventManager.app/Contents/MacOS/EEventManager"]
    private var domain: String { "gui/\(getuid())" }
    private var memo: URL { root.appendingPathComponent("epson-services.json") }
    init(root: URL, diagnostics: Diagnostics) { self.root = root; self.diagnostics = diagnostics }
    private func command(_ args: [String], output: Bool = false) throws -> (Int32, String) {
        let result = try runBoundedProcess(executable: args[0], arguments: Array(args.dropFirst()))
        return (result.status, output ? result.output : "")
    }
    func restore() throws {
        guard FileManager.default.fileExists(atPath: memo.path) else { return }
        let labels = try JSONDecoder().decode([String].self, from: Data(contentsOf: memo))
        for label in labels {
            guard let plist = entries[label] else { throw CocoaError(.fileReadCorruptFile) }
            if try command(["/bin/launchctl", "print", domain + "/" + label]).0 != 0 {
                guard try command(["/bin/launchctl", "bootstrap", domain, plist]).0 == 0 else { throw CocoaError(.fileWriteUnknown) }
            }
        }
        try FileManager.default.removeItem(at: memo)
        diagnostics.record("epson_services_restored")
    }
    func acquire() throws {
        try restore()
        var loaded: [String] = []
        for label in entries.keys.sorted() {
            if try command(["/bin/launchctl", "print", domain + "/" + label]).0 == 0 { loaded.append(label) }
        }
        try JSONEncoder().encode(loaded).write(to: memo, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: memo.path)
        do {
            for label in loaded {
                guard try command(["/bin/launchctl", "bootout", domain + "/" + label]).0 == 0 else { throw CocoaError(.fileWriteUnknown) }
            }
            let output = try command(["/bin/ps", "-axo", "pid=,comm="], output: true).1
            for row in output.split(separator: "\n") {
                let parts = row.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                if parts.count == 2, let pid = Int32(parts[0]), executables.contains(String(parts[1])) { _ = kill(pid, SIGTERM) }
            }
            diagnostics.record("epson_services_taken_over")
        } catch { try? restore(); throw error }
    }
}
