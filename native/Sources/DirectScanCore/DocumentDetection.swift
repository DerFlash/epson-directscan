import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Vision

public struct DocumentRegion: Codable, Equatable {
    public let topLeft: CGPoint
    public let topRight: CGPoint
    public let bottomRight: CGPoint
    public let bottomLeft: CGPoint
    public let confidence: Double
    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint, confidence: Double) {
        self.topLeft=topLeft;self.topRight=topRight;self.bottomRight=bottomRight;self.bottomLeft=bottomLeft;self.confidence=confidence
    }
    var points: [CGPoint] {[topLeft,topRight,bottomRight,bottomLeft]}
    public var bounds: CGRect {
        let x=points.map(\.x),y=points.map(\.y)
        return CGRect(x:x.min()!,y:y.min()!,width:x.max()!-x.min()!,height:y.max()!-y.min()!)
    }
    func validate() throws {
        guard confidence.isFinite,(0...1).contains(confidence),points.allSatisfy({$0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)}),
              bounds.width>=0.02,bounds.height>=0.02 else {throw DocumentDetectionFailure.invalidGeometry}
        for i in 0..<4 {
            let a=points[i],b=points[(i+1)%4],c=points[(i+2)%4]
            guard (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x) < -0.00001 else {throw DocumentDetectionFailure.invalidGeometry}
        }
    }
}

public enum DocumentDetectionFailure: Error, LocalizedError {
    case invalidGeometry, ambiguous, unavailable
    public var errorDescription: String? {
        "Die Dokumentgrenzen konnten nicht sicher erkannt werden. Die vollständige Vorlage bleibt erhalten."
    }
}

public enum DocumentDetection {
    public static let maximumDocumentsPerPage=20
    private static let context=CIContext(options:[.cacheIntermediates:false])
    private static func image(_ input: URL, maximumSize: Int? = nil) throws -> CGImage {
        let decoded=try JPEGInput.decode(input)
        guard decoded.width<=10000,decoded.height<=10000,decoded.width*decoded.height<=16_000_000,
              let source=CGImageSourceCreateWithURL(input as CFURL,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:maximumSize ?? max(decoded.width,decoded.height)] as CFDictionary) else {throw ScanFailure.invalidJPEG}
        return image
    }
    public static func detect(_ input: URL, isCancelled: () -> Bool = {false}, onCheckpoint: () throws -> Void = {}) throws -> [DocumentRegion] {
        try processingCheckpoint(isCancelled,onCheckpoint)
        let image=try image(input,maximumSize:2000),request=VNDetectRectanglesRequest()
        request.maximumObservations=64;request.minimumAspectRatio=0.05;request.maximumAspectRatio=1
        request.minimumSize=0.035;request.minimumConfidence=0.7;request.quadratureTolerance=20
        let deadline=ProcessInfo.processInfo.systemUptime+8
        let cancel=DispatchWorkItem {request.cancel()}
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+8,execute:cancel)
        defer {cancel.cancel()}
        try VNImageRequestHandler(cgImage:image,orientation:.up,options:[:]).perform([request])
        try processingCheckpoint(isCancelled,onCheckpoint)
        guard ProcessInfo.processInfo.systemUptime<deadline else {throw DocumentDetectionFailure.unavailable}
        return try select((request.results ?? []).map {DocumentRegion(topLeft:$0.topLeft,topRight:$0.topRight,bottomRight:$0.bottomRight,bottomLeft:$0.bottomLeft,confidence:Double($0.confidence))})
    }
    public static func select(_ candidates: [DocumentRegion]) throws -> [DocumentRegion] {
        // 64 is the request's observation limit; reaching it cannot prove the
        // candidate set is complete, even if nested frames collapse afterward.
        guard candidates.count<64 else {throw DocumentDetectionFailure.ambiguous}
        try candidates.forEach {try $0.validate()}
        // Tiny groups of printed text lines also form strong rectangles. They
        // must not turn one receipt into several apparently independent items.
        var useful=candidates.filter {$0.confidence>=0.7 && $0.bounds.width>=0.06 && $0.bounds.height>=0.06}
        if useful.count>1 {
            useful.removeAll {let r=$0.bounds;return r.minX<=0.015 && r.minY<=0.015 && r.maxX>=0.985 && r.maxY>=0.985}
        }
        for container in useful {
            let nested=useful.filter {region in
                guard region != container else {return false}
                let b=region.bounds,intersection=container.bounds.intersection(b)
                return !intersection.isNull && intersection.width*intersection.height/(b.width*b.height)>=0.95
            }
            for (index,a) in nested.enumerated() {
                for b in nested.dropFirst(index+1) {
                    let aa=a.bounds,bb=b.bounds,overlap=aa.intersection(bb)
                    if overlap.isNull || overlap.width*overlap.height/min(aa.width*aa.height,bb.width*bb.height)<0.12 {
                        throw DocumentDetectionFailure.ambiguous
                    }
                }
            }
        }
        useful.sort {a,b in
            let aa=a.bounds.width*a.bounds.height,bb=b.bounds.width*b.bounds.height
            return aa == bb ? a.confidence>b.confidence : aa>bb
        }
        var accepted:[DocumentRegion]=[]
        for candidate in useful {
            let b=candidate.bounds,area=b.width*b.height
            if accepted.contains(where: {let overlap=$0.bounds.intersection(b);return !overlap.isNull && overlap.width*overlap.height/area>=0.95}) {continue}
            for other in accepted {
                let r=other.bounds,overlap=r.intersection(b)
                if !overlap.isNull && overlap.width*overlap.height/min(area,r.width*r.height)>0.12 {throw DocumentDetectionFailure.ambiguous}
            }
            accepted.append(candidate)
        }
        guard accepted.count<=maximumDocumentsPerPage else {throw DocumentDetectionFailure.ambiguous}
        // Form explicit rows so the ordering comparator remains transitive.
        var ordered:[DocumentRegion]=[]
        while let top=accepted.map({$0.bounds.maxY}).max() {
            let row=accepted.filter {top-$0.bounds.maxY<=0.04}.sorted {$0.bounds.minX<$1.bounds.minX}
            ordered.append(contentsOf:row);accepted.removeAll {row.contains($0)}
        }
        return ordered
    }
    /// Return the matching back index for each front. Multiple plausible flip
    /// transforms are allowed only when they agree on the document association.
    public static func pair(front:[DocumentRegion],back:[DocumentRegion]) throws -> [Int] {
        guard !front.isEmpty,front.count==back.count,front.count<=maximumDocumentsPerPage,
              try select(front).count==front.count,try select(back).count==back.count else {throw DocumentDetectionFailure.ambiguous}
        var hypotheses:[(score:Double,indices:[Int])]=[]
        for flipX in [false,true] {for flipY in [false,true] {
            var indices:[Int]=[],total=0.0,valid=true
            for f in front {
                let a=f.bounds
                let choices=back.enumerated().map {index,region -> (Int,Double) in
                    let b=region.bounds
                    let centerX=flipX ? 1-b.midX:b.midX,centerY=flipY ? 1-b.midY:b.midY
                    return (index,Double(hypot(a.midX-centerX,a.midY-centerY)+abs(a.width-b.width)+abs(a.height-b.height)))
                }.sorted {$0.1<$1.1}
                guard let best=choices.first,best.1<=0.12,!indices.contains(best.0),
                      choices.count==1 || choices[1].1-best.1>=0.01 else {valid=false;break}
                indices.append(best.0);total+=best.1
            }
            if valid {hypotheses.append((total/Double(front.count),indices))}
        }}
        guard let best=hypotheses.min(by:{$0.score<$1.score}),
              hypotheses.allSatisfy({$0.indices == best.indices}) else {throw DocumentDetectionFailure.ambiguous}
        return best.indices
    }
    public static func write(input: URL, region: DocumentRegion, output: URL,
                             isCancelled: () -> Bool = {false}, onCheckpoint: () throws -> Void = {}) throws {
        try processingCheckpoint(isCancelled,onCheckpoint);try region.validate()
        guard !FileManager.default.fileExists(atPath:output.path) else {throw ScanFailure.collision}
        let image=try image(input),width=CGFloat(image.width),height=CGFloat(image.height)
        func vector(_ point: CGPoint)->CIVector {CIVector(x:point.x*width,y:point.y*height)}
        guard let filter=CIFilter(name:"CIPerspectiveCorrection",parameters:[kCIInputImageKey:CIImage(cgImage:image),
            "inputTopLeft":vector(region.topLeft),"inputTopRight":vector(region.topRight),
            "inputBottomRight":vector(region.bottomRight),"inputBottomLeft":vector(region.bottomLeft)]),
              let corrected=filter.outputImage else {throw DocumentDetectionFailure.invalidGeometry}
        let extent=corrected.extent.integral
        guard !extent.isEmpty,!extent.isInfinite,!extent.isNull,extent.width.isFinite,extent.height.isFinite,
              extent.width<=10000,extent.height<=10000,extent.width*extent.height<=16_000_000,
              let result=context.createCGImage(corrected,from:extent) else {throw DocumentDetectionFailure.invalidGeometry}
        try processingCheckpoint(isCancelled,onCheckpoint)
        let data=NSMutableData()
        guard let writer=CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil) else {throw ScanFailure.invalidJPEG}
        CGImageDestinationAddImage(writer,result,[kCGImageDestinationLossyCompressionQuality:0.95,kCGImagePropertyOrientation:1,
            kCGImagePropertyDPIWidth:300,kCGImagePropertyDPIHeight:300] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else {throw ScanFailure.invalidJPEG}
        try processingCheckpoint(isCancelled,onCheckpoint)
        try (data as Data).write(to:output,options:.withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:output.path)
        let handle=try FileHandle(forWritingTo:output);try handle.synchronize();try handle.close()
    }
}
