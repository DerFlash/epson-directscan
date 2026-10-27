import Testing
import AppKit
import ImageIO
import EpsonImageProcessing

@Suite struct EpsonImageTests {
    @Test func epsonOrientationCorrectsInvertedTextWithoutScannerAccess() throws {
        guard FileManager.default.fileExists(atPath: "/Library/Image Capture/Support/EPSON/Epson Scan 2/Core/ImageProcessor.framework") else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("text.jpg"), output = folder.appendingPathComponent("corrected.jpg")
        let context = try #require(CGContext(data:nil,width:1200,height:1800,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(NSColor.white.cgColor);context.fill(CGRect(x:0,y:0,width:1200,height:1800))
        context.translateBy(x:1200,y:1800);context.rotate(by:.pi)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string:"Automatic document rotation detects readable text.",
            attributes:[.font:NSFont.systemFont(ofSize:36),.foregroundColor:NSColor.black]))
        for n in 0..<30 { context.textPosition=CGPoint(x:45,y:80+n*52);CTLineDraw(line,context) }
        let writer = try #require(CGImageDestinationCreateWithURL(input as CFURL,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(writer,try #require(context.makeImage()),nil);#expect(CGImageDestinationFinalize(writer))
        var orientation: UInt32 = 0
        #expect(EDCorrectJPEG(input.path, output.path, true, &orientation) == 0)
        #expect(orientation == 3)
        var second: UInt32 = 0
        #expect(EDCorrectJPEG(output.path, folder.appendingPathComponent("again.jpg").path, true, &second) == 0)
        #expect(second == 1)
        #expect(EDCorrectJPEG(input.path, folder.appendingPathComponent("unchanged.jpg").path, false, &second) == 0)
        #expect(try Data(contentsOf: input) == Data(contentsOf: folder.appendingPathComponent("unchanged.jpg")))
    }
}
