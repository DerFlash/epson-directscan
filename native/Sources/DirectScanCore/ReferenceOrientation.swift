import Foundation
import CoreGraphics
import ImageIO
import Vision

public struct ReferenceEvidence {
    public let rotation:Int
    public let distance:Double
    public init(rotation:Int,distance:Double){self.rotation=rotation;self.distance=distance}
}

public enum ReferenceDecision {
    private static func winner(_ values:[ReferenceEvidence])->Int? {
        guard values.count==4,Set(values.map(\.rotation))==Set([0,90,180,270]),
              values.allSatisfy({$0.distance.isFinite && $0.distance>=0}) else {return nil}
        let sorted=values.sorted{$0.distance<$1.distance},best=sorted[0],next=sorted[1]
        guard best.distance<=12,next.distance>0,(next.distance-best.distance)/next.distance>=0.20 else {return nil}
        return best.rotation
    }
    public static func resolve(text:OrientationResult,front:[ReferenceEvidence],back:[ReferenceEvidence]?,mapping:DuplexMapping?,fallbackFront:Int,fallbackBack:Int,printedOffset:Int=0)->OrientationResult {
        if [.conflict,.uncalibrated,.missingPair].contains(text.notice) {return text}
        let a=winner(front),b=back.flatMap(winner)
        func fallback(_ reason:OrientationNotice)->OrientationResult {
            OrientationResult(front:fallbackFront,back:back == nil ? nil:fallbackBack,notice:reason)
        }
        if text.notice == nil {
            if a.map({$0 != text.front}) ?? false || b.map({$0 != text.back}) ?? false {return fallback(.conflict)}
            return text
        }
        guard back != nil else {
            return a.map{OrientationResult(front:$0,back:nil,notice:nil)} ?? text
        }
        guard let mapping,mapping.isValid else {return fallback(.uncalibrated)}
        if let a,let b,mapping.back(for:a,printedOffset:printedOffset) != b {return fallback(.conflict)}
        let angle=a ?? b.flatMap { value in [0,90,180,270].first{mapping.back(for:$0,printedOffset:printedOffset)==value} }
        guard let angle else {return text}
        return OrientationResult(front:angle,back:mapping.back(for:angle,printedOffset:printedOffset),notice:nil)
    }
}

/// A local image reference, stored only as a secure Vision feature print. No
/// image, filesystem path, recognized text or external model is persisted.
public enum ReferenceMatcher {
    private static func image(_ url:URL)throws->CGImage {
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
        guard let bytes=try file.read(upToCount:32*1024*1024+1),bytes.count<=32*1024*1024,
              let source=CGImageSourceCreateWithData(bytes as CFData,nil),CGImageSourceGetCount(source)==1,
              let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],
              let w=(props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let h=(props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
              w>0,h>0,w<=10000,h<=10000,w*h<=16_000_000,
              let result=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1200] as CFDictionary) else {throw ScanFailure.invalidJPEG}
        return result
    }
    private static func perform(_ request:VNRequest,image:CGImage,deadline:TimeInterval)throws {
        let remaining=deadline-ProcessInfo.processInfo.systemUptime
        guard remaining>0 else {throw CocoaError(.userCancelled)}
        let cancel=DispatchWorkItem{request.cancel()}
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+remaining,execute:cancel)
        defer{cancel.cancel()}
        try VNImageRequestHandler(cgImage:image,orientation:.up,options:[:]).perform([request])
        guard ProcessInfo.processInfo.systemUptime<deadline else {throw CocoaError(.userCancelled)}
    }
    private static func feature(_ image:CGImage,deadline:TimeInterval)throws->VNFeaturePrintObservation {
        let request=VNGenerateImageFeaturePrintRequest();request.revision=VNGenerateImageFeaturePrintRequestRevision1
        try perform(request,image:image,deadline:deadline)
        guard let result=request.results?.first else {throw ScanFailure.invalidSource}
        return result
    }
    public static func makeReference(_ url:URL)throws->Data {
        let source=try image(url)
        let print=try feature(source,deadline:ProcessInfo.processInfo.systemUptime+3)
        let bytes=try NSKeyedArchiver.archivedData(withRootObject:print,requiringSecureCoding:true)
        guard !bytes.isEmpty,bytes.count<=262144 else {throw ScanFailure.invalidSettings}
        return bytes
    }
    private static func decode(_ data:Data)throws->VNFeaturePrintObservation {
        guard (32...262144).contains(data.count),data.starts(with:Data("bplist00".utf8)),
              let print=try NSKeyedUnarchiver.unarchivedObject(ofClass:VNFeaturePrintObservation.self,from:data),
              print.requestRevision==VNGenerateImageFeaturePrintRequestRevision1,
              print.elementCount>0,print.elementCount<=8192 else {throw ScanFailure.invalidSettings}
        return print
    }
    public static func analyze(_ url:URL,reference:Data)throws->[ReferenceEvidence] {
        let reference=try decode(reference),source=try image(url)
        let deadline=ProcessInfo.processInfo.systemUptime+3
        return try [0,90,180,270].map { angle in
            try autoreleasepool {
                let candidate=try PageRotation.rotated(source,degrees:angle)
                let request=VNDetectRectanglesRequest();request.maximumObservations=5
                request.minimumConfidence=0.5;request.minimumAspectRatio=0.5;request.maximumAspectRatio=0.9;request.minimumSize=0.3
                try perform(request,image:candidate,deadline:deadline)
                var regions=[candidate]
                for rectangle in request.results ?? [] {
                    let b=rectangle.boundingBox,w=CGFloat(candidate.width),h=CGFloat(candidate.height)
                    let crop=CGRect(x:b.minX*w,y:(1-b.maxY)*h,width:b.width*w,height:b.height*h).integral
                        .intersection(CGRect(x:0,y:0,width:w,height:h))
                    if crop.width>=1,crop.height>=1,let part=candidate.cropping(to:crop){regions.append(part)}

                }
                var best=Double.infinity
                for region in regions {
                    let observed=try feature(region,deadline:deadline);var distance:Float=0
                    try reference.computeDistance(&distance,to:observed)
                    guard distance.isFinite,distance>=0 else {throw ScanFailure.invalidSource}
                    best=min(best,Double(distance))
                }
                return ReferenceEvidence(rotation:angle,distance:best)
            }
        }
    }
}
