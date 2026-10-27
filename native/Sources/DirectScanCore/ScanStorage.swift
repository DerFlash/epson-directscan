import Foundation
import ImageIO
import Darwin
import CryptoKit

public struct ScanJob: Codable {
    public let id: UUID
    public let directory: URL
    public let destination: URL
    public let fileStem: String
    public let settings: ScanSettings
    public func outputURL(page: Int) -> URL {
        destination.appendingPathComponent(String(format: "%@_%04d.jpg", fileStem, page))
    }
}

private struct JobRecord: Codable {
    let job: ScanJob
    var publishedSources: [String] = []
    var manifest: PageManifest?
    var receipts: [ExportReceipt]? = []
}

private struct ExportReceipt: Codable {
    let sources: [String]
    let targetName: String
    let temporaryName: String
    let inode: UInt64
    let device: UInt64
    let digest: String
    var published: Bool
}

public final class ScanStorage {
    public let root: URL
    public var pendingDirectory: URL { root.appendingPathComponent("Pending", isDirectory: true) }
    public var recoveryDirectory: URL { root.appendingPathComponent("Recovery", isDirectory: true) }
    private let fm = FileManager.default
    public init(root: URL) throws {
        self.root = root.standardizedFileURL
        for folder in [self.root, pendingDirectory, recoveryDirectory] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func loadSettings() throws -> ScanSettings {
        let path = root.appendingPathComponent("settings.json")
        guard fm.fileExists(atPath: path.path) else { return ScanSettings() }
        do {
            let data = try Data(contentsOf: path)
            let settings = try JSONDecoder().decode(ScanSettings.self, from: data)
            try settings.validate()
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["schemaVersion"] as? Int == 1 {
                let backup = root.appendingPathComponent("settings-v1-backup.json")
                // Never replace a previous backup, including after an interrupted migration.
                if !fm.fileExists(atPath: backup.path) {
                    try data.write(to: backup, options: .withoutOverwriting)
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                }
                try write(settings, to: path)
            }
            return settings
        } catch { throw ScanFailure.invalidSettings }
    }
    public func saveSettings(_ settings: ScanSettings) throws {
        try settings.validate()
        try write(settings, to: root.appendingPathComponent("settings.json"))
    }
    public func validateDestination(_ path: String?) throws -> URL {
        guard let path, path.hasPrefix("/") else { throw ScanFailure.invalidDestination }
        let destination = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fm.isWritableFile(atPath: destination.path) else { throw ScanFailure.invalidDestination }
        return destination
    }
    public func hasUnfinishedJobs() throws -> Bool {
        try !fm.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil).isEmpty
    }
    public func beginJob(settings: ScanSettings) throws -> ScanJob {
        try settings.validate()
        guard try !hasUnfinishedJobs() else { throw ScanFailure.unfinishedPages }
        let destination = try validateDestination(settings.destination)
        let id = UUID()
        let directory = pendingDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let stem = "Karte_" + formatter.string(from: Date()) + "_" + id.uuidString
        let job = ScanJob(id: id, directory: directory, destination: destination, fileStem: stem, settings: settings)
        try write(JobRecord(job: job, manifest: PageManifest(duplex: settings.duplex)), to: directory.appendingPathComponent("job.json"))
        return job
    }
    private func record(_ job: ScanJob) throws -> JobRecord {
        let expected = pendingDirectory.appendingPathComponent(job.id.uuidString, isDirectory: true)
        guard job.directory.standardizedFileURL == expected.standardizedFileURL else { throw ScanFailure.invalidSource }
        return try JSONDecoder().decode(JobRecord.self, from: Data(contentsOf: job.directory.appendingPathComponent("job.json")))
    }
    public func manifest(job: ScanJob) throws -> PageManifest {
        guard let manifest = try record(job).manifest else { throw ScanFailure.invalidSource }
        return manifest
    }
    private func localSource(_ source: URL, job: ScanJob) throws {
        guard source.standardizedFileURL.deletingLastPathComponent() == job.directory.standardizedFileURL,
              source.resolvingSymlinksInPath() == source.standardizedFileURL,
              source.lastPathComponent != "job.json" else { throw ScanFailure.invalidSource }
    }
    public func stage(source: URL, job: ScanJob, sheet: Int, side: PageSide) throws {
        var record = try record(job)
        try localSource(source, job: job)
        let image = try JPEGInput.decode(source)
        guard var manifest = record.manifest else { throw ScanFailure.invalidSource }
        try manifest.append(ValidatedPage(index: manifest.pages.count+1, sheet: sheet, side: side,
            sourceName: source.lastPathComponent, width: image.width, height: image.height))
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        let handle = try FileHandle(forWritingTo: source); try handle.synchronize(); try handle.close()
        record.manifest = manifest
        try write(record, to: job.directory.appendingPathComponent("job.json"))
    }
    public func complete(job: ScanJob, reason: JobEndReason) throws {
        var record = try record(job)
        guard var manifest = record.manifest, manifest.endReason == nil, !manifest.pages.isEmpty else { throw ScanFailure.unfinishedPages }
        if !job.settings.automaticFeeding && manifest.hasIncompleteSheet { throw ScanFailure.incompletePair }
        manifest.endReason = reason; record.manifest = manifest
        try write(record, to: job.directory.appendingPathComponent("job.json"))
    }
    private func fingerprint(_ url: URL) throws -> (UInt64, UInt64, String) {
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ScanFailure.invalidSource }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024*1024), !bytes.isEmpty { hash.update(data: bytes) }
        return ((attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    private func matches(_ url: URL, _ receipt: ExportReceipt) throws -> Bool {
        guard fm.fileExists(atPath: url.path), url.resolvingSymlinksInPath() == url.standardizedFileURL else { return false }
        let value = try fingerprint(url)
        return value.0 == receipt.inode && value.1 == receipt.device && value.2 == receipt.digest
    }
    /// Reentrant export: a receipt identifies the actual renamed inode, including a crash before acknowledgement.
    public func export(job: ScanJob, allowInterrupted: Bool = false, asCollection: Bool = false) throws -> [URL] {
        var record = try record(job)
        guard let manifest = record.manifest, let reason = manifest.endReason, !manifest.pages.isEmpty,
              reason != .interrupted || allowInterrupted else { throw ScanFailure.unfinishedPages }
        if !job.settings.automaticFeeding && !asCollection && manifest.hasIncompleteSheet { throw ScanFailure.incompletePair }
        _ = try validateDestination(job.destination.path)
        let groups: [[ValidatedPage]]
        let collection = job.settings.automaticFeeding || asCollection
        let pdf = collection || job.settings.outputFormat == .pdf
        if collection { groups = [manifest.pages] }
        else if pdf { groups = Dictionary(grouping: manifest.pages, by: \.sheet).sorted { $0.key < $1.key }.map(\.value) }
        else { groups = manifest.pages.map { [$0] } }
        var outputs: [URL] = []
        for group in groups {
            let number = String(format: "%04d", group[0].sheet)
            let name: String
            if collection { name = job.fileStem + "_Sammlung.pdf" }
            else if pdf { name = job.fileStem + "_" + number + ".pdf" }
            else { name = job.fileStem + "_" + number + (job.settings.duplex ? (group[0].side == .front ? "_vorne" : "_hinten") : "") + ".jpg" }
            let target = job.destination.appendingPathComponent(name)
            let sources = group.map(\.sourceName)
            if let index = (record.receipts ?? []).firstIndex(where: { $0.targetName == name }) {
                var receipt = record.receipts![index]
                guard receipt.sources == sources else { throw ScanFailure.invalidSource }
                if try !matches(target, receipt) {
                    guard !receipt.published else { throw ScanFailure.invalidSource }
                    let temp = job.destination.appendingPathComponent(receipt.temporaryName)
                    guard try matches(temp, receipt) else { throw ScanFailure.unfinishedPages }
                    guard renamex_np(temp.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
                        if errno == EEXIST { throw ScanFailure.collision }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                }
                receipt.published = true; record.receipts![index] = receipt
            } else {
                guard !fm.fileExists(atPath: target.path) else { throw ScanFailure.collision }
                for page in group { try localSource(job.directory.appendingPathComponent(page.sourceName), job: job) }
                let temporary = job.destination.appendingPathComponent(".directscan-" + UUID().uuidString + ".tmp")
                let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
                guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                Darwin.close(descriptor)
                var journaled = false
                defer { if !journaled { try? fm.removeItem(at: temporary) } }
                if pdf { try PDFOutput.write(pages: group.map { job.directory.appendingPathComponent($0.sourceName) }, to: temporary, dpi: 300) }
                else {
                    let source = job.directory.appendingPathComponent(group[0].sourceName)
                    _ = try JPEGInput.decode(source)
                    try Data(contentsOf: source).write(to: temporary)
                }
                let handle = try FileHandle(forWritingTo: temporary); try handle.synchronize(); try handle.close()
                let value = try fingerprint(temporary)
                guard value.0 != 0 else { throw ScanFailure.invalidSource }
                var receipt = ExportReceipt(sources: sources, targetName: name, temporaryName: temporary.lastPathComponent,
                    inode: value.0, device: value.1, digest: value.2, published: false)
                if record.receipts == nil { record.receipts = [] }; record.receipts!.append(receipt)
                try write(record, to: job.directory.appendingPathComponent("job.json")); journaled = true
                guard renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
                    if errno == EEXIST { throw ScanFailure.collision }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                receipt.published = true; record.receipts![record.receipts!.count-1] = receipt
            }
            try write(record, to: job.directory.appendingPathComponent("job.json"))
            outputs.append(target)
        }
        return outputs
    }
    public func pendingJobs() throws -> [ScanJob] {
        try fm.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }.map {
            let record = try JSONDecoder().decode(JobRecord.self, from: Data(contentsOf: $0.appendingPathComponent("job.json")))
            _ = try self.record(record.job)
            return record.job
        }
    }
    /// Explicit user action only; never invoked on launch or scanner reconnection.
    public func recoverCollection(job: ScanJob) throws -> [URL] {
        var record = try record(job)
        guard var manifest = record.manifest, !manifest.pages.isEmpty,
              (record.receipts ?? []).isEmpty else { throw ScanFailure.unfinishedPages }
        manifest.endReason = .interrupted; record.manifest = manifest
        try write(record, to: job.directory.appendingPathComponent("job.json"))
        return try export(job: job, allowInterrupted: true, asCollection: true)
    }
    public func publish(source: URL, job: ScanJob, page: Int) throws -> URL {
        var record = try record(job)
        guard page > 0, source.resolvingSymlinksInPath().deletingLastPathComponent() == job.directory.resolvingSymlinksInPath(),
              source.lastPathComponent != "job.json", !record.publishedSources.contains(source.lastPathComponent) else { throw ScanFailure.invalidSource }
        let attributes = try fm.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue > 4, size.intValue < 300 * 1024 * 1024 else { throw ScanFailure.invalidJPEG }
        let data = try Data(contentsOf: source)
        guard data.starts(with: [0xff,0xd8]), data.suffix(2).elementsEqual([0xff,0xd9]),
              let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) == 1,
              CGImageSourceGetType(image) as String? == "public.jpeg", CGImageSourceGetStatus(image) == .statusComplete,
              let decoded = CGImageSourceCreateImageAtIndex(image, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              decoded.width > 0, decoded.height > 0, CGImageSourceGetStatusAtIndex(image, 0) == .statusComplete else { throw ScanFailure.invalidJPEG }
        _ = try validateDestination(job.destination.path)
        let target = job.outputURL(page: page)
        let temporary = job.destination.appendingPathComponent(".directscan-" + UUID().uuidString + ".tmp")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { try? fm.removeItem(at: temporary) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw ScanFailure.collision }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        record.publishedSources.append(source.lastPathComponent)
        try write(record, to: job.directory.appendingPathComponent("job.json"))
        return target
    }
    public func finish(job: ScanJob) throws {
        let record = try record(job)
        let remaining = try fm.contentsOfDirectory(at: job.directory, includingPropertiesForKeys: nil)
        if let manifest = record.manifest, !manifest.pages.isEmpty {
            let receipts = record.receipts ?? []
            let names = Set(receipts.flatMap(\.sources))
            guard manifest.endReason != nil, !receipts.isEmpty, receipts.allSatisfy(\.published),
                  Set(manifest.pages.map(\.sourceName)) == names,
                  remaining.allSatisfy({ $0.lastPathComponent == "job.json" || names.contains($0.lastPathComponent) }) else { throw ScanFailure.unfinishedPages }
            for receipt in receipts { guard try matches(job.destination.appendingPathComponent(receipt.targetName), receipt) else { throw ScanFailure.unfinishedPages } }
            let directory = root.appendingPathComponent("Receipts", isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try write(record, to: directory.appendingPathComponent(job.id.uuidString + ".json"))
            try fm.removeItem(at: job.directory)
            return
        }
        guard !record.publishedSources.isEmpty,
              remaining.allSatisfy({ $0.lastPathComponent == "job.json" || record.publishedSources.contains($0.lastPathComponent) }) else { throw ScanFailure.unfinishedPages }
        try fm.removeItem(at: job.directory)
    }
    public func acknowledgeRecovery() throws {
        for job in try fm.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil) {
            try fm.moveItem(at: job, to: recoveryDirectory.appendingPathComponent(job.lastPathComponent))
        }
    }
}
