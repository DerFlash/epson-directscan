import Foundation
import CoreGraphics
import ImageIO

enum JPEGInput {
    static func decode(_ url: URL) throws -> CGImage {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeRegular,
              let size = a[.size] as? NSNumber, size.intValue > 4, size.intValue < 300 * 1024 * 1024 else { throw ScanFailure.invalidJPEG }
        let data = try Data(contentsOf: url)
        guard data.starts(with: [255,216]), data.suffix(2).elementsEqual([255,217]),
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == "public.jpeg", CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width > 0, image.height > 0, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw ScanFailure.invalidJPEG }
        return image
    }
}

public enum PDFOutput {
    public static func write(pages: [URL], to output: URL, dpi: Double) throws {
        guard !pages.isEmpty, dpi.isFinite, dpi > 0 else { throw ScanFailure.invalidPDF }
        guard let consumer = CGDataConsumer(url: output as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ScanFailure.invalidPDF }
        var geometry: [CGRect] = []
        do {
            for source in pages {
                try autoreleasepool {
                    let image = try JPEGInput.decode(source)
                    var box = CGRect(x: 0, y: 0, width: Double(image.width) * 72 / dpi, height: Double(image.height) * 72 / dpi)
                    let data = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
                    context.beginPDFPage([kCGPDFContextMediaBox as String: data] as CFDictionary)
                    context.draw(image, in: box)
                    context.endPDFPage()
                    geometry.append(box)
                }
            }
            context.closePDF()
            guard let document = CGPDFDocument(output as CFURL), document.numberOfPages == pages.count else { throw ScanFailure.invalidPDF }
            for index in geometry.indices {
                guard let page = document.page(at: index+1) else { throw ScanFailure.invalidPDF }
                let actual = page.getBoxRect(.mediaBox), expected = geometry[index]
                // Quartz may return 177.60000000000002 for a written 177.6pt box.
                // Tolerance is below 1/2000 of a 300dpi pixel, while still rejecting
                // a genuinely different page size or origin.
                guard zip([actual.minX,actual.minY,actual.width,actual.height],
                          [expected.minX,expected.minY,expected.width,expected.height])
                    .allSatisfy({ abs($0 - $1) < 0.0001 }) else { throw ScanFailure.invalidPDF }
            }
        } catch {
            context.closePDF()
            throw error
        }
    }
}
