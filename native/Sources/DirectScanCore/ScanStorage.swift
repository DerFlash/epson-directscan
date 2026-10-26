import Foundation
import ImageIO
import Darwin

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
            let settings = try JSONDecoder().decode(ScanSettings.self, from: Data(contentsOf: path))
            try settings.validate()
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
        try write(JobRecord(job: job), to: directory.appendingPathComponent("job.json"))
        return job
    }
    private func record(_ job: ScanJob) throws -> JobRecord {
        let expected = pendingDirectory.appendingPathComponent(job.id.uuidString, isDirectory: true)
        guard job.directory.standardizedFileURL == expected.standardizedFileURL else { throw ScanFailure.invalidSource }
        return try JSONDecoder().decode(JobRecord.self, from: Data(contentsOf: job.directory.appendingPathComponent("job.json")))
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
              decoded.width > 0, decoded.height > 0 else { throw ScanFailure.invalidJPEG }
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
