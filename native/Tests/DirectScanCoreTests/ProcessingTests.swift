import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import DirectScanCore

@Suite struct ProcessingTests {
    func settings(_ destination: URL, duplex: Bool = false) -> ScanSettings {
        var s = ScanSettings(destination:destination.path), p = ScanProfile(name:"Test")
        p.frontRotation = 90; p.backRotation = 270
        s.profiles = [p]; s.activeProfileID = p.id; s.duplex = duplex
        return s
    }
    @Test func actualPixelsRotateAndMetadataMatches() throws {
        let f = try StorageTests(), input = f.root.appendingPathComponent("input.jpg")
        let bytes = (0..<80*40).flatMap { i -> [UInt8] in
            let left = i%80 < 40, top = i/80 < 20
            return top ? (left ? [255,0,0,255] : [0,255,0,255]) : (left ? [0,0,255,255] : [255,255,255,255])
        }
        let provider = try #require(CGDataProvider(data:Data(bytes) as CFData))
        let image = try #require(CGImage(width:80,height:40,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:320,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let writer = try #require(CGImageDestinationCreateWithURL(input as CFURL,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(writer,image,[kCGImageDestinationLossyCompressionQuality:1] as CFDictionary)
        #expect(CGImageDestinationFinalize(writer))
        func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
            let small = try #require(image.cropping(to:CGRect(x:x,y:y,width:1,height:1)))
            var data = [UInt8](repeating:0,count:4)
            let context = try #require(CGContext(data:&data,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
            context.draw(small,in:CGRect(x:0,y:0,width:1,height:1)); return Array(data.prefix(3))
        }
        for (angle,w,h,redX,redY) in [(90,40,80,30,10),(180,80,40,70,30),(270,40,80,10,70)] {
            let out = f.root.appendingPathComponent("\(angle).jpg")
            try PageRotation.write(input:input,output:out,degrees:angle)
            let result = try JPEGInput.decode(out)
            #expect(result.width == w && result.height == h)
            let red = try pixel(result,redX,redY)
            #expect(red[0] > 220 && red[1] < 35 && red[2] < 35)
            let src = try #require(CGImageSourceCreateWithURL(out as CFURL,nil))
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [String:Any])
            #expect((props[kCGImagePropertyDPIWidth as String] as? NSNumber)?.intValue == 300)
            // ImageIO may omit the normal EXIF orientation (whose default is1).
            #expect(((props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1) == 1)
            #expect(throws: (any Error).self) { try PageRotation.write(input:input,output:out,degrees:angle) }
        }
        let same = f.root.appendingPathComponent("same.jpg")
        try PageRotation.write(input:input,output:same,degrees:0)
        #expect(try Data(contentsOf:input) == Data(contentsOf:same))
    }
    @Test func processedExportRetryNeverRotatesAgainAndKeepsOriginalUntilFinish() throws {
        let f = try StorageTests(), store = try f.store(), output = try f.destination()
        let job = try store.beginJob(settings:settings(output))
        let source = job.directory.appendingPathComponent("input.jpg");try f.jpeg(source,width:80,height:40)
        let original = try Data(contentsOf:source)
        try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        let first = try store.export(job:job), bytes = try Data(contentsOf:first[0])
        #expect(try JPEGInput.decode(first[0]).width == 40)
        #expect(try store.export(job:job) == first)
        let retried = try Data(contentsOf:first[0]), retained = try Data(contentsOf:source)
        #expect(retried == bytes && retained == original)
        try store.finish(job:job)
        #expect(try !store.hasUnfinishedJobs())
    }
    @Test func pairInferenceUsesOtherSideAndRejectsChangedOriginalAfterPreparation() throws {
        let f = try StorageTests(), store = try f.store(), output = try f.destination()
        var s = settings(output,duplex:true)
        s.profiles[0].orientation = .vision;s.profiles[0].icaMapping = DuplexMapping(sign:-1,offset:0)
        let job = try store.beginJob(settings:s)
        for (name,side) in [("front.jpg",PageSide.front),("back.jpg",.back)] {
            let url = job.directory.appendingPathComponent(name);try f.jpeg(url,width:80,height:40)
            try store.stage(source:url,job:job,sheet:1,side:side)
        }
        try store.complete(job:job,reason:.completed)
        try store.prepareImages(job:job,analyze:{ url in
            [0,90,180,270].map { OrientationEvidence(rotation:$0,score:url.lastPathComponent == "back.jpg" && $0 == 270 ? 60 : 0,lines:url.lastPathComponent == "back.jpg" && $0 == 270 ? 4 : 0) }
        })
        #expect(try store.processingNotice(job:job).isEmpty)
        let urls = try store.export(job:job)
        let a = try JPEGInput.decode(urls[0]), b = try JPEGInput.decode(urls[1])
        #expect(urls.count == 2 && a.width == 40 && b.width == 40)
        try f.jpeg(job.directory.appendingPathComponent("front.jpg"),width:90,height:40)
        #expect(throws: (any Error).self) { try store.export(job:job) }
    }
    @Test func partialProcessingJournalCanRetryWithoutLosingOrphansOrOriginals() throws {
        let f = try StorageTests(), store = try f.store(), output = try f.destination()
        let job = try store.beginJob(settings:settings(output))
        for i in 1...2 { let u = job.directory.appendingPathComponent("\(i).jpg");try f.jpeg(u,width:80,height:40);try store.stage(source:u,job:job,sheet:i,side:.front) }
        try store.complete(job:job,reason:.completed)
        #expect(throws: (any Error).self) { try store.prepareImages(job:job,onProgress:{ _ in throw CocoaError(.userCancelled) }) }
        #expect(try FileManager.default.contentsOfDirectory(atPath:output.path).isEmpty)
        let files = try store.export(job:job)
        let first = try JPEGInput.decode(files[0])
        #expect(files.count == 2 && first.width == 40)
        try store.finish(job:job)
        #expect(try !store.hasUnfinishedJobs())
    }
    @Test func uncalibratedPairFallsBackWithNoticeAndDoesNotCallOCR() throws {
        let f = try StorageTests(), store = try f.store(), output = try f.destination()
        var s = settings(output,duplex:true);s.profiles[0].orientation = .vision
        let job = try store.beginJob(settings:s)
        for (n,side) in [("a.jpg",PageSide.front),("b.jpg",.back)] { let u = job.directory.appendingPathComponent(n);try f.jpeg(u,width:80,height:40);try store.stage(source:u,job:job,sheet:1,side:side) }
        try store.complete(job:job,reason:.completed)
        var calls = 0
        try store.prepareImages(job:job,analyze:{ _ in calls += 1;throw CocoaError(.fileReadUnknown) })
        #expect(calls == 0)
        #expect(try store.processingNotice(job:job) == [.uncalibrated])
        #expect(try store.export(job:job).count == 2)
    }
    @Test func escapedManifestIsRejectedBeforeCallingAnalyzer() throws {
        let f = try StorageTests(), store = try f.store(), output = try f.destination()
        var s = settings(output);s.profiles[0].orientation = .vision
        let job = try store.beginJob(settings:s), source = job.directory.appendingPathComponent("a.jpg")
        try f.jpeg(source,width:80,height:40);try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        var record = try store.record(job)
        record.manifest!.pages = [ValidatedPage(index:1,sheet:1,side:.front,sourceName:"../outside.jpg",width:80,height:40)]
        try JSONEncoder().encode(record).write(to:job.directory.appendingPathComponent("job.json"))
        var calls = 0
        #expect(throws:(any Error).self) { try store.prepareImages(job:job,analyze:{ _ in calls += 1;return [] }) }
        #expect(calls == 0)
    }
    @Test func rotatedPDFHasSwappedPhysicalPageDimensions() throws {
        let f = try StorageTests(), store = try f.store(), output = try f.destination()
        var s = settings(output);s.outputFormat = .pdf
        let job = try store.beginJob(settings:s), source = job.directory.appendingPathComponent("a.jpg")
        try f.jpeg(source,width:80,height:40);try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        let files = try store.export(job:job), doc = try #require(CGPDFDocument(files[0] as CFURL))
        let box = try #require(doc.page(at:1)).getBoxRect(.mediaBox)
        #expect(abs(box.width-9.6) < 0.0001 && abs(box.height-19.2) < 0.0001)
    }
    @Test func cancelledProcessingCannotPublishAndCanLaterRecoverFromOriginals() throws {
        let f = try StorageTests(), store = try f.store(), output = try f.destination()
        let job = try store.beginJob(settings:settings(output)), source = job.directory.appendingPathComponent("a.jpg")
        try f.jpeg(source,width:80,height:40);try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        try store.prepareImages(job:job)
        #expect(throws:(any Error).self) {try store.export(job:job,isCancelled:{true})}
        #expect(try FileManager.default.contentsOfDirectory(atPath:output.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath:source.path))
        #expect(try store.export(job:job).count == 1)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIRECTSCAN_ORIENTATION_SAMPLES"] != nil))
    func productionAnalyzerReproducesPrivateSampleMatrix() throws {
        let path = try #require(ProcessInfo.processInfo.environment["DIRECTSCAN_ORIENTATION_SAMPLES"])
        let samples = try #require(JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))) as? [[String:Any]])
        let f = try StorageTests()
        for sample in samples {
            let input = URL(fileURLWithPath:try #require(sample["path"] as? String))
            for angle in [0,90,180,270] {
                let variant = f.root.appendingPathComponent(UUID().uuidString+".jpg")
                try PageRotation.write(input:input,output:variant,degrees:angle)
                let scores = try VisionOrientation.analyze(variant)
                let result = OrientationDecision.resolve(front:scores,back:nil,mapping:nil,fallbackFront:0,fallbackBack:0)
                if sample["side"] as? String == "front" { #expect(result.front == (360-angle)%360 && result.notice == nil) }
                else { #expect(result.notice == .uncertain) }
            }
        }
    }
}
