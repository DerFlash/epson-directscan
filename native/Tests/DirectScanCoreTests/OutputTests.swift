import Testing
import CoreGraphics
import Foundation
@testable import DirectScanCore

@Suite final class OutputTests {
    let fixture: StorageTests
    init() throws { fixture = try StorageTests() }

    @Test func legacySettingsMigrateWithExactBackupAndSafeDefaults() throws {
        let store = try fixture.store()
        let original = Data(#"{"schemaVersion":1,"destination":"/tmp","paused":true,"crop":false,"deskew":true,"rotate":false}"#.utf8)
        try original.write(to: store.root.appendingPathComponent("settings.json"))
        let settings = try store.loadSettings()
        #expect(settings.schemaVersion == 2)
        #expect(settings.destination == "/tmp" && settings.paused && !settings.crop && !settings.rotate)
        #expect(!settings.duplex && settings.outputFormat == .jpg && !settings.automaticFeeding)
        #expect(settings.feedingTimeoutSeconds == 120)
        let backup = store.root.appendingPathComponent("settings-v1-backup.json")
        #expect(try Data(contentsOf: backup) == original)
        _ = try store.loadSettings()
        #expect(try Data(contentsOf: backup) == original)
        var invalid = settings; invalid.feedingTimeoutSeconds = 17
        #expect(throws: (any Error).self) { try store.saveSettings(invalid) }
    }

    @Test func pdfPreservesPageOrderGeometryAndCanRender() throws {
        let a = fixture.root.appendingPathComponent("a.jpg"), b = fixture.root.appendingPathComponent("b.jpg")
        try fixture.jpeg(a, width: 300, height: 600)
        try fixture.jpeg(b, width: 600, height: 300)
        let output = fixture.root.appendingPathComponent("out.pdf")
        try PDFOutput.write(pages: [a,b], to: output, dpi: 300)
        let pdf = try #require(CGPDFDocument(output as CFURL))
        #expect(pdf.numberOfPages == 2)
        let first = try #require(pdf.page(at: 1)), second = try #require(pdf.page(at: 2))
        #expect(first.getBoxRect(.mediaBox) == CGRect(x: 0,y: 0,width: 72,height: 144))
        #expect(second.getBoxRect(.mediaBox) == CGRect(x: 0,y: 0,width: 144,height: 72))
        let context = try #require(CGContext(data: nil, width: 144, height: 144, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.drawPDFPage(first)
        #expect(context.makeImage() != nil)
    }
    @Test func croppedCardPixelDimensionsProduceFourReadablePDFPages() throws {
        let dimensions = [(741,1033),(740,1030),(749,1037),(744,1034)]
        var pages: [URL] = []
        for (index,size) in dimensions.enumerated() {
            let file = fixture.root.appendingPathComponent("card\(index).jpg")
            try fixture.jpeg(file, width: size.0, height: size.1); pages.append(file)
        }
        let output = fixture.root.appendingPathComponent("collection.pdf")
        try PDFOutput.write(pages: pages, to: output, dpi: 300)
        let pdf = try #require(CGPDFDocument(output as CFURL))
        #expect(pdf.numberOfPages == 4)
        for (index,size) in dimensions.enumerated() {
            let page = try #require(pdf.page(at: index+1))
            let box = page.getBoxRect(.mediaBox)
            #expect(abs(box.width - Double(size.0)*72/300) < 0.0001)
            #expect(abs(box.height - Double(size.1)*72/300) < 0.0001)
        }
    }

    @Test func duplexPDFRequiresBothSidesAndPublishesOnce() throws {
        let store = try fixture.store(), output = try fixture.destination()
        var settings = ScanSettings(destination: output.path); settings.duplex = true; settings.outputFormat = .pdf
        let job = try store.beginJob(settings: settings)
        let front = job.directory.appendingPathComponent("front.jpg"), back = job.directory.appendingPathComponent("back.jpg")
        try fixture.jpeg(front, width: 30, height: 60); try fixture.jpeg(back, width: 60, height: 30)
        try store.stage(source: front, job: job, sheet: 1, side: .front)
        #expect(throws: (any Error).self) { try store.complete(job: job, reason: .completed) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        try store.stage(source: back, job: job, sheet: 1, side: .back)
        try store.complete(job: job, reason: .completed)
        let files = try store.export(job: job)
        #expect(files.count == 1 && files.first?.pathExtension == "pdf")
        #expect(try #require(CGPDFDocument(files[0] as CFURL)).numberOfPages == 2)
        #expect(try store.export(job: job) == files)
        #expect(FileManager.default.fileExists(atPath: front.path))
        try store.finish(job: job)
        #expect(try !store.hasUnfinishedJobs())
        #expect(try !FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("Receipts").path).isEmpty)
    }

    @Test func jpgSidesShareCardNumberAndCollectionKeepsCompletePages() throws {
        let store = try fixture.store(), output = try fixture.destination()
        var settings = ScanSettings(destination: output.path); settings.duplex = true
        let job = try store.beginJob(settings: settings)
        for (name,side) in [("front.jpg", PageSide.front),("back.jpg", .back)] {
            let url = job.directory.appendingPathComponent(name); try fixture.jpeg(url)
            try store.stage(source: url, job: job, sheet: 1, side: side)
        }
        try store.complete(job: job, reason: .completed)
        let files = try store.export(job: job)
        #expect(files.map(\.lastPathComponent) == [job.fileStem + "_0001_vorne.jpg", job.fileStem + "_0001_hinten.jpg"])
        try store.finish(job: job)
        settings.automaticFeeding = true
        let collection = try store.beginJob(settings: settings)
        for index in 1...3 {
            let url = collection.directory.appendingPathComponent("page\(index).jpg"); try fixture.jpeg(url)
            try store.stage(source: url, job: collection, sheet: (index+1)/2, side: index % 2 == 1 ? .front : .back)
        }
        // A stop may leave the final sheet without a back; all completed pages remain exportable.
        try store.complete(job: collection, reason: .stop)
        let collected = try store.export(job: collection)
        #expect(collected.count == 1)
        #expect(try #require(CGPDFDocument(collected[0] as CFURL)).numberOfPages == 3)
        #expect(try store.manifest(job: collection).hasIncompleteSheet)
    }

    @Test func duplicateSideTruncationCollisionAndLostFolderRetainPages() throws {
        let store = try fixture.store(), output = try fixture.destination()
        var settings = ScanSettings(destination: output.path); settings.outputFormat = .pdf
        let job = try store.beginJob(settings: settings)
        let source = job.directory.appendingPathComponent("page.jpg"); try fixture.jpeg(source, width: 128, height: 128)
        let original = try Data(contentsOf: source)
        try (Data(original.prefix(original.count/2)) + Data([255,217])).write(to: source)
        #expect(throws: (any Error).self) { try store.stage(source: source, job: job, sheet: 1, side: .front) }
        try original.write(to: source)
        try store.stage(source: source, job: job, sheet: 1, side: .front)
        #expect(throws: (any Error).self) { try store.stage(source: source, job: job, sheet: 1, side: .front) }
        try store.complete(job: job, reason: .completed)
        let target = output.appendingPathComponent(job.fileStem + "_0001.pdf")
        let existing = Data("existing".utf8); try existing.write(to: target)
        #expect(throws: (any Error).self) { try store.export(job: job) }
        #expect(try Data(contentsOf: target) == existing)
        try FileManager.default.removeItem(at: output)
        #expect(throws: (any Error).self) { try store.export(job: job) }
        #expect(try Data(contentsOf: source) == original)
        #expect(try ScanStorage(root: store.root).hasUnfinishedJobs())
    }

    @Test func recoveryReconcilesRenameBeforeAcknowledgementAndRefusesReplacement() throws {
        let store = try fixture.store(), output = try fixture.destination()
        let job = try store.beginJob(settings: ScanSettings(destination: output.path))
        let source = job.directory.appendingPathComponent("page.jpg"); try fixture.jpeg(source)
        try store.stage(source: source, job: job, sheet: 1, side: .front)
        try store.complete(job: job, reason: .completed)
        let files = try store.export(job: job)
        let journal = job.directory.appendingPathComponent("job.json")
        var value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String:Any])
        var receipts = try #require(value["receipts"] as? [[String:Any]])
        receipts[0]["published"] = false; value["receipts"] = receipts
        try JSONSerialization.data(withJSONObject: value).write(to: journal)
        let restarted = try ScanStorage(root: store.root)
        #expect(try restarted.export(job: job) == files)
        let identical = try Data(contentsOf: files[0])
        let replacement = output.appendingPathComponent("replacement")
        try identical.write(to: replacement)
        try FileManager.default.removeItem(at: files[0]); try FileManager.default.moveItem(at: replacement, to: files[0])
        #expect(throws: (any Error).self) { try restarted.export(job: job) }
        #expect(throws: (any Error).self) { try restarted.finish(job: job) }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func interruptedPagesRequireExplicitRecoveryExport() throws {
        let store = try fixture.store(), output = try fixture.destination()
        var settings = ScanSettings(destination: output.path); settings.automaticFeeding = true
        let job = try store.beginJob(settings: settings)
        let source = job.directory.appendingPathComponent("page.jpg"); try fixture.jpeg(source)
        try store.stage(source: source, job: job, sheet: 1, side: .front)
        #expect(throws: (any Error).self) { try store.export(job: job) }
        let recovered = try store.recoverCollection(job: job)
        #expect(recovered.count == 1)
        #expect(try #require(CGPDFDocument(recovered[0] as CFURL)).numberOfPages == 1)
        #expect(try store.manifest(job: job).endReason == .interrupted)
        #expect(try store.pendingJobs().map(\.id) == [job.id])
    }
    @Test func interruptedNormalRecoveryRetainsCollectionGroupingAcrossRestart() throws {
        let store = try fixture.store()
        for format in [OutputFormat.jpg, .pdf] {
            let output = try fixture.destination(format.rawValue)
            var settings = ScanSettings(destination: output.path); settings.outputFormat = format; settings.duplex = true
            let job = try store.beginJob(settings: settings)
            for (name,side) in [("front.jpg",PageSide.front),("back.jpg",.back)] {
                let source = job.directory.appendingPathComponent(name); try fixture.jpeg(source)
                try store.stage(source: source, job: job, sheet: 1, side: side)
            }
            let first = try store.recoverCollection(job: job)
            #expect(first.count == 1 && first[0].lastPathComponent.hasSuffix("_Sammlung.pdf"))
            // Also exercise publication before receipt acknowledgement for the PDF setting.
            if format == .pdf {
                let journal = job.directory.appendingPathComponent("job.json")
                var value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String:Any])
                var receipts = try #require(value["receipts"] as? [[String:Any]])
                receipts[0]["published"] = false; value["receipts"] = receipts
                try JSONSerialization.data(withJSONObject: value).write(to: journal)
            }
            let restarted = try ScanStorage(root: store.root)
            let retried: [URL]
            // The same retry path as the app's recovery action.
            do { retried = try restarted.recoverCollection(job: job) }
            catch { retried = try restarted.export(job: job, allowInterrupted: true) }
            #expect(retried == first)
            #expect(try FileManager.default.contentsOfDirectory(atPath: output.path) == [first[0].lastPathComponent])
            try restarted.finish(job: job)
        }
    }
}
