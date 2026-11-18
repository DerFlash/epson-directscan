import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import DirectScanCore

@Suite struct DocumentProcessingTests {
    func settings(_ output:URL,duplex:Bool=false)->ScanSettings {
        var s=ScanSettings(destination:output.path),p=ScanProfile(name:"Belege")
        p.orientation = .vision;p.separateDocuments=true;s.profiles=[p];s.activeProfileID=p.id;s.outputFormat = .pdf;s.duplex=duplex
        return s
    }
    var regions:[DocumentRegion] {
        let detector=DocumentDetectionTests()
        return [detector.region(CGRect(x:0.1,y:0.55,width:0.3,height:0.35)),detector.region(CGRect(x:0.6,y:0.6,width:0.3,height:0.25)),detector.region(CGRect(x:0.2,y:0.1,width:0.5,height:0.3))]
    }
    func evidence(_ url:URL)throws->[OrientationEvidence] {
        let image=try JPEGInput.decode(url),angle=image.height>image.width ? 90:0
        return [0,90,180,270].map{OrientationEvidence(rotation:$0,score:$0==angle ? 60:0,lines:$0==angle ? 4:0)}
    }
    @Test func threeDocumentsGetIndependentRotationPDFsAndFullSourceArchive() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination(),job=try store.beginJob(settings:settings(out))
        let source=job.directory.appendingPathComponent("full.jpg");try f.jpeg(source,width:1000,height:1400)
        let original=try Data(contentsOf:source)
        try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        try store.prepareImages(job:job,analyze:evidence,detectDocuments:{_ in regions})
        let files=try store.export(job:job)
        #expect(files.map(\.lastPathComponent)==[job.fileStem+"_0001.pdf",job.fileStem+"_0002.pdf",job.fileStem+"_0003.pdf"])
        let expected=[CGSize(width:117.6,height:72),CGSize(width:84,height:72),CGSize(width:120,height:100.8)]
        for (file,size) in zip(files,expected) {
            let pdf=try #require(CGPDFDocument(file as CFURL));#expect(pdf.numberOfPages==1)
            let rect=try #require(pdf.page(at:1)).getBoxRect(.mediaBox)
            #expect(abs(rect.width-size.width)<1 && abs(rect.height-size.height)<1)
        }
        let bytes=try files.map {try Data(contentsOf:$0)}
        #expect(try store.export(job:job)==files)
        #expect(try files.map {try Data(contentsOf:$0)} == bytes)
        try store.finish(job:job)
        #expect(try !store.hasUnfinishedJobs())
        #expect(try Data(contentsOf:store.originalsDirectory.appendingPathComponent(job.id.uuidString).appendingPathComponent("full.jpg"))==original)
    }
    @Test func uncertainSeparationCanRecoverWholePagesAndPreservesOriginal() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination(),job=try store.beginJob(settings:settings(out))
        let source=job.directory.appendingPathComponent("full.jpg");try f.jpeg(source,width:1000,height:1400)
        let original=try Data(contentsOf:source)
        try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        #expect(throws:(any Error).self) {try store.prepareImages(job:job,detectDocuments:{_ in []})}
        #expect(try FileManager.default.contentsOfDirectory(atPath:out.path).isEmpty)
        let files=try store.recoverCollection(job:job)
        #expect(files.count==1 && files[0].lastPathComponent.hasSuffix("_Sammlung.pdf"))
        let pdf=try #require(CGPDFDocument(files[0] as CFURL));#expect(pdf.numberOfPages==1)
        let bounds=try #require(pdf.page(at:1)).getBoxRect(.mediaBox)
        #expect(abs(bounds.width-240)<0.1 && abs(bounds.height-336)<0.1)
        try store.finish(job:job)
        #expect(try Data(contentsOf:store.originalsDirectory.appendingPathComponent(job.id.uuidString).appendingPathComponent("full.jpg"))==original)
    }
    @Test func duplexPDFsContainTheMatchingBackPixelsAndContinuousJPGStaysSeparate() throws {
        let r=DocumentDetectionTests()
        let front=[r.region(CGRect(x:0.1,y:0.65,width:0.25,height:0.25)),r.region(CGRect(x:0.65,y:0.55,width:0.25,height:0.35)),r.region(CGRect(x:0.2,y:0.1,width:0.5,height:0.25))]
        let back=[r.region(CGRect(x:0.65,y:0.65,width:0.25,height:0.25)),r.region(CGRect(x:0.1,y:0.55,width:0.25,height:0.35)),r.region(CGRect(x:0.3,y:0.1,width:0.5,height:0.25))]
        let colors:[[CGFloat]]=[[1,0,0],[0,1,0],[0,0,1],[0,1,1],[1,0,1],[1,1,0]]
        let colorSpace=try #require(CGColorSpace(name:CGColorSpace.sRGB))
        let f=try StorageTests(),store=try f.store(),out=try f.destination()
        var s=settings(out,duplex:true);s.profiles[0].orientation = .fixed
        let job=try store.beginJob(settings:s)
        for (name,side,rects,start) in [("front.jpg",PageSide.front,front,0),("back.jpg",.back,back,3)] {
            let context=try #require(CGContext(data:nil,width:1000,height:1400,bitsPerComponent:8,bytesPerRow:0,
                space:colorSpace,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(CGColor(gray:0.3,alpha:1));context.fill(CGRect(x:0,y:0,width:1000,height:1400))
            for (i,region) in rects.enumerated() {
                let color=colors[start+i];context.setFillColor(try #require(CGColor(colorSpace:colorSpace,components:color+[1])))
                let b=region.bounds;context.fill(CGRect(x:b.minX*1000,y:b.minY*1400,width:b.width*1000,height:b.height*1400))
            }
            let source=job.directory.appendingPathComponent(name),writer=try #require(CGImageDestinationCreateWithURL(source as CFURL,"public.jpeg" as CFString,1,nil))
            CGImageDestinationAddImage(writer,try #require(context.makeImage()),[kCGImageDestinationLossyCompressionQuality:1] as CFDictionary);try #require(CGImageDestinationFinalize(writer))
            try store.stage(source:source,job:job,sheet:1,side:side)
        }
        try store.complete(job:job,reason:.completed)
        try store.prepareImages(job:job,detectDocuments:{$0.lastPathComponent=="front.jpg" ? front:back})
        let files=try store.export(job:job);#expect(files.count==3)
        for (i,file) in files.enumerated() {
            let pdf=try #require(CGPDFDocument(file as CFURL));#expect(pdf.numberOfPages==2)
            for side in 0...1 {
                let page=try #require(pdf.page(at:side+1)),box=page.getBoxRect(.mediaBox)
                var bytes=[UInt8](repeating:0,count:64*64*4)
                let sample=try #require(CGContext(data:&bytes,width:64,height:64,bitsPerComponent:8,bytesPerRow:64*4,
                    space:colorSpace,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
                sample.scaleBy(x:64/box.width,y:64/box.height);sample.drawPDFPage(page)
                let wanted=colors[i+side*3]
                for channel in 0..<3 {#expect(abs(Double(bytes[(32*64+32)*4+channel])-Double(wanted[channel]*255))<25,"Document \(i+1), side \(side), RGB \(Array(bytes[((32*64+32)*4)..<((32*64+32)*4+3)]))")}
            }
        }
        try store.finish(job:job)
        s.duplex=false;s.automaticFeeding=true;s.outputFormat = .jpg
        let next=try store.beginJob(settings:s),source=next.directory.appendingPathComponent("front.jpg")
        try f.jpeg(source,width:1000,height:1400);try store.stage(source:source,job:next,sheet:1,side:.front);try store.complete(job:next,reason:.stop)
        try store.prepareImages(job:next,detectDocuments:{_ in front})
        let jpgs=try store.export(job:next)
        #expect(jpgs.count==3 && jpgs.allSatisfy {$0.pathExtension=="jpg" && !$0.lastPathComponent.contains("Sammlung")})
    }
    @Test func partialProcessingCanRetryAndIncompleteJournalCannotPublishOrDeleteSource() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination(),job=try store.beginJob(settings:settings(out))
        let source=job.directory.appendingPathComponent("full.jpg");try f.jpeg(source,width:1000,height:1400)
        let original=try Data(contentsOf:source)
        try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        #expect(throws:(any Error).self) {try store.prepareImages(job:job,analyze:evidence,detectDocuments:{_ in regions},onProgress:{_ in throw CocoaError(.userCancelled)})}
        #expect(try Data(contentsOf:source)==original)
        try store.prepareImages(job:job,analyze:evidence,detectDocuments:{_ in regions})
        let path=job.directory.appendingPathComponent("job.json")
        var json=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        var processing=try #require(json["documentProcessing"] as? [String:Any])
        var pages=try #require(processing["pages"] as? [[String:Any]]);pages.removeLast();processing["pages"]=pages;json["documentProcessing"]=processing
        try JSONSerialization.data(withJSONObject:json).write(to:path)
        #expect(throws:(any Error).self) {try store.export(job:job)}
        #expect(throws:(any Error).self) {try store.finish(job:job)}
        #expect(try FileManager.default.contentsOfDirectory(atPath:out.path).isEmpty)
        #expect(try Data(contentsOf:source)==original)
    }
}
