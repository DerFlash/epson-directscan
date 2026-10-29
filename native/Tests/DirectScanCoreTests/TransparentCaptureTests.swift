import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import DirectScanCore
@testable import EpsonDirectScan

func transparentProfile(width:Double = 50.8,height:Double = 76.2) throws -> ScanProfile {
    var p=ScanProfile(name:"Hülle");p.area=ScanArea(widthMM:width,heightMM:height)
    var json=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as? [String:Any])
    json["transparentOriginal"]=true
    return try JSONDecoder().decode(ScanProfile.self,from:JSONSerialization.data(withJSONObject:json))
}

@Suite struct TransparentCaptureTests {
    @Test func transparentCanvasKeepsPixelScaleAndCentersBothAxes() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination()
        let source=out.appendingPathComponent("marker.jpg"),target=out.appendingPathComponent("canvas.jpg")
        let pixels=(0..<500*800).flatMap { i -> [UInt8] in
            let x=i%500,y=i/500
            if x<40 && y<40 {return [255,0,0,255]}
            if x>=460 && y>=760 {return [0,0,255,255]}
            return [0,255,0,255]
        }
        let provider=try #require(CGDataProvider(data:Data(pixels) as CFData))
        let image=try #require(CGImage(width:500,height:800,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:2000,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let writer=try #require(CGImageDestinationCreateWithURL(source as CFURL,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(writer,image,[kCGImageDestinationLossyCompressionQuality:1] as CFDictionary)
        #expect(CGImageDestinationFinalize(writer))
        try PageRotation.write(input:source,output:target,degrees:0,fixedArea:ScanArea(widthMM:50.8,heightMM:76.2),transparentCanvas:true)
        let result=try JPEGInput.decode(target)
        func pixel(_ x:Int,_ y:Int) throws -> [UInt8] {
            let point=try #require(result.cropping(to:CGRect(x:x,y:y,width:1,height:1)))
            var value=[UInt8](repeating:0,count:4)
            let c=try #require(CGContext(data:&value,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
            c.draw(point,in:CGRect(x:0,y:0,width:1,height:1));return value
        }
        //500x800 must sit at50,50 on a600x900 canvas, rather than filling it.
        let red=try pixel(70,70),blue=try pixel(530,830),white=try pixel(20,20),green=try pixel(100,100)
        #expect(red[0]>220 && red[1]<35 && red[2]<35)
        #expect(blue[2]>220 && blue[0]<35 && blue[1]<35)
        #expect(white.prefix(3).allSatisfy{$0>240})
        #expect(green[1]>220 && green[0]<35 && green[2]<35)
        _=store // Own the fixture lifetime while inspecting its files.
    }
    @Test func transparentFixedProfileAcquiresOuterHolderInsteadOfTruncatingAtOpaqueCard() throws {
        let p=try transparentProfile();var s=ScanSettings(destination:"/tmp")
        s.profiles=[p];s.activeProfileID=p.id
        #expect(s.driverCrop && !s.driverDeskew && !s.driverRotate)
        let payload=try #require(JSONSerialization.jsonObject(with:NativeProcess.feedingPayload(s)) as? [String:Any])
        #expect(payload["crop"] as? Bool == true)
        #expect(payload["transparentOriginal"] as? Bool == true)
        #expect(payload["singleShot"] as? Bool == true)
        #expect(try JSONDecoder().decode(ScanSettings.self,from:JSONEncoder().encode(s)) == s)
        var invalid=p;invalid.area=ScanArea();invalid.orientation = .epson
        #expect(throws:(any Error).self) {try invalid.validateForCapture()}
    }

    @Test func transparentCanvasPadsSmallerCaptureWithoutScalingAndRetriesIdentically() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination()
        var s=ScanSettings(destination:out.path);let p=try transparentProfile();s.profiles=[p];s.activeProfileID=p.id
        let job=try store.beginJob(settings:s),source=job.directory.appendingPathComponent("holder.jpg")
        try f.jpeg(source,width:500,height:800)
        let original=try Data(contentsOf:source)
        try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        try store.prepareImages(job:job)
        let files=try store.export(job:job),image=try JPEGInput.decode(files[0])
        #expect(image.width == 600 && image.height == 900)
        #expect(job.fixedFrameCaptureRevision == 2)
        let first=try Data(contentsOf:files[0]);#expect(try store.export(job:job)==files)
        #expect(try Data(contentsOf:files[0])==first && Data(contentsOf:source)==original)
        let r=try store.record(job);#expect(r.processing?.fixedFrameRevision == 2)
        try store.finish(job:job);#expect(try !store.hasUnfinishedJobs())
    }

    @Test func transparentCanvasCannotDiscardPixelsBeyondKnownCaptureMargin() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination()
        var s=ScanSettings(destination:out.path);let p=try transparentProfile();s.profiles=[p];s.activeProfileID=p.id
        let job=try store.beginJob(settings:s),source=job.directory.appendingPathComponent("holder.jpg")
        //600x900 canvas cannot contain the680x1080 protected area of this800x1200 scan.
        try f.jpeg(source,width:800,height:1200);let bytes=try Data(contentsOf:source)
        try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        #expect(throws:(any Error).self) {try store.export(job:job)}
        #expect(try FileManager.default.contentsOfDirectory(atPath:out.path).isEmpty)
        #expect(try Data(contentsOf:source)==bytes && store.hasUnfinishedJobs())
    }

    @Test func historicalNonTransparentCaptureCannotBeReinterpretedAsCompleteHolder() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination()
        var s=ScanSettings(destination:out.path);var p=ScanProfile(name:"Alt");p.area=ScanArea(widthMM:50.8,heightMM:76.2)
        s.profiles=[p];s.activeProfileID=p.id
        let job=try store.beginJob(settings:s),source=job.directory.appendingPathComponent("old.jpg")
        try f.jpeg(source,width:600,height:900);try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        let path=job.directory.appendingPathComponent("job.json")
        var record=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        var saved=try #require(record["job"] as? [String:Any]);var prefs=try #require(saved["settings"] as? [String:Any])
        var profiles=try #require(prefs["profiles"] as? [[String:Any]]);profiles[0]["transparentOriginal"]=true
        prefs["profiles"]=profiles;saved["settings"]=prefs;record["job"]=saved
        try JSONSerialization.data(withJSONObject:record).write(to:path)
        let retained=try #require(store.pendingJobs().first)
        #expect(throws:(any Error).self) {try store.export(job:retained)}
        #expect(FileManager.default.fileExists(atPath:source.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath:out.path).isEmpty)
    }
}
