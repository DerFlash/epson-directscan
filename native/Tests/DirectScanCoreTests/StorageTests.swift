import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import DirectScanCore

@Suite final class StorageTests {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func store() throws -> ScanStorage { try ScanStorage(root: root.appendingPathComponent("private")) }
    func destination(_ name: String = "output") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func jpeg(_ url: URL) throws {
        let pixels = Data([255, 100, 0, 255])
        let provider = CGDataProvider(data: pixels as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, image, nil)
        #expect(CGImageDestinationFinalize(writer))
    }
    @Test func testSettingsRoundtripAndCorruptionIsNotSilentlyReset() throws {
        let s = try store()
        #expect(try s.loadSettings().destination == nil)
        var settings = ScanSettings(destination: try destination().path)
        settings.rotate = false
        try s.saveSettings(settings)
        #expect(try s.loadSettings() == settings)
        try Data("broken".utf8).write(to: s.root.appendingPathComponent("settings.json"))
        #expect(throws: (any Error).self) { try s.loadSettings() }
    }
    @Test func testValidJpegPublishesToFrozenFolderAndSourceIsRetainedUntilJobCompletion() throws {
        let s = try store(), output = try destination()
        var settings = ScanSettings(destination: output.path)
        let job = try s.beginJob(settings: settings)
        settings.destination = try destination("other").path
        let source = job.directory.appendingPathComponent("page.jpeg")
        try jpeg(source)
        let published = try s.publish(source: source, job: job, page: 1)
        #expect(published.deletingLastPathComponent().path == output.path)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: source) == Data(contentsOf: published))
        #expect(try s.hasUnfinishedJobs())
        try s.finish(job: job)
        #expect(try !s.hasUnfinishedJobs())
        #expect(FileManager.default.fileExists(atPath: published.path))
    }
    @Test func testCollisionDoesNotReplaceExistingFile() throws {
        let s = try store(), output = try destination()
        let job = try s.beginJob(settings: ScanSettings(destination: output.path))
        let source = job.directory.appendingPathComponent("page.jpeg"); try jpeg(source)
        let target = job.outputURL(page: 1)
        let previous = Data("existing".utf8); try previous.write(to: target)
        #expect(throws: (any Error).self) { try s.publish(source: source, job: job, page: 1) }
        #expect(try Data(contentsOf: target) == previous)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
    @Test func testInvalidTruncatedAndOutsideJobJpegsNeverPublish() throws {
        let s = try store(), output = try destination()
        let job = try s.beginJob(settings: ScanSettings(destination: output.path))
        let source = job.directory.appendingPathComponent("page.jpeg")
        try Data([0xff,0xd8,0xff,0xd9]).write(to: source)
        #expect(throws: (any Error).self) { try s.publish(source: source, job: job, page: 1) }
        try jpeg(source)
        var data = try Data(contentsOf: source); data.removeLast(20); try data.write(to: source)
        #expect(throws: (any Error).self) { try s.publish(source: source, job: job, page: 1) }
        let outside = root.appendingPathComponent("elsewhere.jpeg"); try jpeg(outside)
        #expect(throws: (any Error).self) { try s.publish(source: outside, job: job, page: 1) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }
    @Test func testLostDestinationAndRestartKeepRecoverableSource() throws {
        let s = try store(), output = try destination()
        let job = try s.beginJob(settings: ScanSettings(destination: output.path))
        let source = job.directory.appendingPathComponent("page.jpeg"); try jpeg(source)
        try FileManager.default.removeItem(at: output)
        #expect(throws: (any Error).self) { try s.publish(source: source, job: job, page: 1) }
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try ScanStorage(root: s.root).hasUnfinishedJobs())
    }
}
