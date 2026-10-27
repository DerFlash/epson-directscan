import Foundation
import CoreGraphics
import ImageIO
import Vision

public enum PageRotation {
    static func rotated(_ image: CGImage, degrees: Int) throws -> CGImage {
        guard [0,90,180,270].contains(degrees), image.width*image.height <= 16_000_000 else { throw ScanFailure.invalidJPEG }
        if degrees == 0 { return image }
        let swapped = degrees == 90 || degrees == 270
        let w = swapped ? image.height : image.width, h = swapped ? image.width : image.height
        guard let context = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ScanFailure.invalidJPEG }
        context.translateBy(x:CGFloat(w)/2,y:CGFloat(h)/2)
        context.rotate(by:-CGFloat(degrees)*CGFloat.pi/180)
        let width = CGFloat(image.width), height = CGFloat(image.height)
        context.draw(image,in:CGRect(x:-width/2,y:-height/2,width:width,height:height))
        guard let result = context.makeImage() else { throw ScanFailure.invalidJPEG }
        return result
    }
    public static func write(input: URL, output: URL, degrees: Int) throws {
        guard [0,90,180,270].contains(degrees), !FileManager.default.fileExists(atPath:output.path),
              let source = CGImageSourceCreateWithURL(input as CFURL,nil) else { throw ScanFailure.invalidSource }
        let original = try JPEGInput.decode(input)
        guard original.width <= 10000, original.height <= 10000, original.width*original.height <= 16_000_000 else { throw ScanFailure.invalidJPEG }
        let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any] ?? [:]
        let orientation = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        if degrees == 0 && orientation == 1 {
            try Data(contentsOf:input).write(to:output,options:.withoutOverwriting)
        } else {
            guard let normalized = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max(original.width,original.height)] as CFDictionary) else { throw ScanFailure.invalidJPEG }
            let image = try rotated(normalized,degrees:degrees)
            let data = NSMutableData()
            guard let writer = CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil) else { throw ScanFailure.invalidJPEG }
            CGImageDestinationAddImage(writer,image,[kCGImageDestinationLossyCompressionQuality:0.95,kCGImagePropertyDPIWidth:300,kCGImagePropertyDPIHeight:300,kCGImagePropertyOrientation:1] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw ScanFailure.invalidJPEG }
            try (data as Data).write(to:output,options:.withoutOverwriting)
        }
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:output.path)
        let handle = try FileHandle(forWritingTo:output);try handle.synchronize();try handle.close()
    }
}

public enum VisionOrientation {
    public static func analyze(_ input: URL) throws -> [OrientationEvidence] {
        guard let source = CGImageSourceCreateWithURL(input as CFURL,nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1200] as CFDictionary) else { throw ScanFailure.invalidJPEG }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        return try [0,90,180,270].map { angle in
            try autoreleasepool {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw CocoaError(.userCancelled) }
                let candidate = try PageRotation.rotated(image,degrees:angle)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .fast
                request.recognitionLanguages = ["de-DE","en-US"]
                request.usesLanguageCorrection = false;request.minimumTextHeight = 0.008
                let cancel = DispatchWorkItem { request.cancel() }
                DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+max(0,deadline-ProcessInfo.processInfo.systemUptime),execute:cancel)
                defer { cancel.cancel() }
                try VNImageRequestHandler(cgImage:candidate,orientation:.up,options:[:]).perform([request])
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw CocoaError(.userCancelled) }
                var score = 0.0, lines = 0
                for observation in request.results ?? [] {
                    guard let text = observation.topCandidates(1).first else { continue }
                    let count = text.string.filter { $0.isLetter || $0.isNumber }.count
                    let confidence = Double(text.confidence)
                    if count >= 3 { lines += 1 }
                    if confidence.isFinite { score += Double(min(count,40))*confidence*confidence }
                }
                return OrientationEvidence(rotation:angle,score:score,lines:lines)
            }
        }
    }
}
