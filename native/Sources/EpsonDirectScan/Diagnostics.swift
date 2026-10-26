import Foundation

final class Diagnostics {
    let root: URL
    init(root: URL) { self.root = root }
    func record(_ code: String, values: [String: Int] = [:]) {
        var item: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "code": code]
        item["values"] = values
        guard let data = try? JSONSerialization.data(withJSONObject: item) else { return }
        let url = root.appendingPathComponent("events.jsonl")
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber, size.intValue > 128_000 {
            let old = root.appendingPathComponent("events.previous.jsonl")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do { try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10])) } catch {}
        }
    }
    func status(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        let url = root.appendingPathComponent("status.json")
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
