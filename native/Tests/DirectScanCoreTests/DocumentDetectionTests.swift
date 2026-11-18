import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import DirectScanCore

@Suite struct DocumentDetectionTests {
    func region(_ rect: CGRect, confidence: Double = 0.95) -> DocumentRegion {
        DocumentRegion(topLeft: CGPoint(x:rect.minX,y:rect.maxY), topRight: CGPoint(x:rect.maxX,y:rect.maxY),
                       bottomRight: CGPoint(x:rect.maxX,y:rect.minY), bottomLeft: CGPoint(x:rect.minX,y:rect.minY), confidence:confidence)
    }
    @Test func selectionRemovesSleeveAndNestedFramesAndOrdersDocuments() throws {
        let a=region(CGRect(x:0.1,y:0.6,width:0.3,height:0.3)),b=region(CGRect(x:0.6,y:0.6,width:0.3,height:0.25))
        let c=region(CGRect(x:0.2,y:0.1,width:0.5,height:0.3))
        let nested=region(CGRect(x:0.15,y:0.65,width:0.15,height:0.1)),sleeve=region(CGRect(x:0,y:0,width:1,height:1))
        let found=try DocumentDetection.select([c,nested,b,sleeve,a])
        #expect(found == [a,b,c])
    }
    @Test func ambiguousAndInvalidGeometryCannotAuthorizeCrops() throws {
        let a=region(CGRect(x:0.1,y:0.1,width:0.5,height:0.5)),overlap=region(CGRect(x:0.4,y:0.4,width:0.5,height:0.5))
        #expect(throws:(any Error).self) {try DocumentDetection.select([a,overlap])}
        #expect(throws:(any Error).self) {try DocumentDetection.select([region(CGRect(x:-0.2,y:0,width:0.4,height:0.4))])}
        #expect(throws:(any Error).self) {try DocumentDetection.select([region(CGRect(x:0,y:0,width:0,height:0.4))])}
        #expect(throws:(any Error).self) {try DocumentDetection.select(Array(repeating:a,count:65))}
        #expect(try DocumentDetection.select([region(CGRect(x:0.1,y:0.1,width:0.4,height:0.4),confidence:0.1)]).isEmpty)
    }
    @Test func actualVisionFindsThreeSeparatePaperRegions() throws {
        let fixture=try StorageTests(),input=fixture.root.appendingPathComponent("sheet.jpg")
        let context=try #require(CGContext(data:nil,width:1500,height:1800,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray:0.22,alpha:1));context.fill(CGRect(x:0,y:0,width:1500,height:1800))
        let papers=[CGRect(x:100,y:1050,width:500,height:600),CGRect(x:850,y:1250,width:500,height:350),CGRect(x:350,y:150,width:700,height:500)]
        for rect in papers {
            context.setFillColor(CGColor(gray:0.98,alpha:1));context.fill(rect)
            context.setFillColor(CGColor(gray:0.15,alpha:1))
            for line in 1...7 {context.fill(CGRect(x:rect.minX+30,y:rect.maxY-CGFloat(line)*30,width:rect.width-60,height:4))}
        }
        let image=try #require(context.makeImage()),writer=try #require(CGImageDestinationCreateWithURL(input as CFURL,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(writer,image,[kCGImageDestinationLossyCompressionQuality:1] as CFDictionary);try #require(CGImageDestinationFinalize(writer))
        let found=try DocumentDetection.detect(input)
        #expect(found.count == 3)
        for rect in papers {
            #expect(found.contains {abs($0.bounds.width-rect.width/1500)<0.025 && abs($0.bounds.height-rect.height/1800)<0.025})
        }
    }
    @Test func correctedCropContainsOnlyItsOwnPixelsAndDoesNotOverwrite() throws {
        let fixture=try StorageTests(),input=fixture.root.appendingPathComponent("sheet.jpg"),output=fixture.root.appendingPathComponent("document.jpg")
        let context=try #require(CGContext(data:nil,width:800,height:600,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1));context.fill(CGRect(x:0,y:0,width:800,height:600))
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));context.fill(CGRect(x:200,y:150,width:400,height:300))
        let writer=try #require(CGImageDestinationCreateWithURL(input as CFURL,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(writer,try #require(context.makeImage()),[kCGImageDestinationLossyCompressionQuality:1] as CFDictionary);try #require(CGImageDestinationFinalize(writer))
        try DocumentDetection.write(input:input,region:region(CGRect(x:0.25,y:0.25,width:0.5,height:0.5)),output:output)
        let result=try JPEGInput.decode(output)
        #expect(abs(result.width-400)<=2 && abs(result.height-300)<=2)
        var pixel=[UInt8](repeating:0,count:4)
        let sample=try #require(CGContext(data:&pixel,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        sample.draw(result,in:CGRect(x:0,y:0,width:1,height:1));#expect(pixel[0]>220 && pixel[2]<30)
        let original=try Data(contentsOf:output)
        #expect(throws:(any Error).self) {try DocumentDetection.write(input:input,region:region(CGRect(x:0,y:0,width:1,height:1)),output:output)}
        #expect(try Data(contentsOf:output)==original)
    }
}
