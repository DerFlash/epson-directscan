import Foundation

struct DocumentSourceRecord: Codable {
    let index:Int
    let name:String
    let digest:String
    let regions:[DocumentRegion]
}
struct ProcessedDocumentPage: Codable {
    let sourceIndex:Int
    let regionIndex:Int
    let page:ValidatedPage
    let digest:String
}
struct DocumentProcessingRecord: Codable {
    let revision:Int
    let sources:[DocumentSourceRecord]
    let pages:[ProcessedDocumentPage]
    let notices:[OrientationNotice]
}
private struct DocumentPlacement {
    let sourceIndex:Int
    let regionIndex:Int
    let sheet:Int
    let side:PageSide
}

extension ScanStorage {
    private func documentPlacements(_ sources:[DocumentSourceRecord],manifest:PageManifest) throws -> [DocumentPlacement] {
        guard sources.count==manifest.pages.count,!sources.isEmpty else {throw ScanFailure.invalidSource}
        var validated=PageManifest(duplex:manifest.duplex)
        for raw in manifest.pages {try validated.append(raw)}
        for (source,raw) in zip(sources,manifest.pages) {
            guard source.index==raw.index,source.name==raw.sourceName,!source.regions.isEmpty,
                  try DocumentDetection.select(source.regions)==source.regions else {throw ScanFailure.invalidSource}
        }
        let groups=Dictionary(grouping:manifest.pages,by:\.sheet).sorted {$0.key<$1.key}
        var result:[DocumentPlacement]=[],number=0
        for (_,pages) in groups {
            guard let front=pages.first(where:{$0.side == .front}),front.index>0,front.index<=sources.count else {throw ScanFailure.invalidSource}
            let frontRegions=sources[front.index-1].regions
            let back=pages.first {$0.side == .back}
            var matched:[Int]=[]
            if manifest.duplex {
                guard let back,back.index>0,back.index<=sources.count else {throw DocumentDetectionFailure.ambiguous}
                matched=try DocumentDetection.pair(front:frontRegions,back:sources[back.index-1].regions)
            } else if back != nil {throw ScanFailure.invalidSource}
            for index in frontRegions.indices {
                number+=1
                result.append(DocumentPlacement(sourceIndex:front.index,regionIndex:index,sheet:number,side:.front))
                if let back {result.append(DocumentPlacement(sourceIndex:back.index,regionIndex:matched[index],sheet:number,side:.back))}
            }
        }
        return result
    }
    func checkedDocuments(_ record:JobRecord,job:ScanJob,isCancelled:()->Bool,onCheckpoint:()throws->Void) throws -> PageManifest? {
        guard let processed=record.documentProcessing else {return nil}
        guard processed.revision==1,record.processing==nil,let original=record.manifest,original.endReason != nil else {throw ScanFailure.invalidSource}
        let placements=try documentPlacements(processed.sources,manifest:original)
        guard processed.pages.count==placements.count,Set(processed.pages.map { $0.page.sourceName }).count==processed.pages.count else {throw ScanFailure.invalidSource}
        for (source,raw) in zip(processed.sources,original.pages) {
            let url=job.directory.appendingPathComponent(source.name)
            try localSource(url,job:job)
            guard try fingerprint(url,isCancelled:isCancelled,onCheckpoint:onCheckpoint).2==source.digest else {throw ScanFailure.invalidSource}
            let image=try JPEGInput.decode(url)
            guard image.width==raw.width,image.height==raw.height else {throw ScanFailure.invalidSource}
        }
        let originalNames=Set(original.pages.map(\.sourceName))
        for (offset,pair) in zip(placements,processed.pages).enumerated() {
            try processingCheckpoint(isCancelled,onCheckpoint)
            let (placement,result)=pair,page=result.page,url=job.directory.appendingPathComponent(page.sourceName)
            guard result.sourceIndex==placement.sourceIndex,result.regionIndex==placement.regionIndex,
                  page.index==offset+1,page.sheet==placement.sheet,page.side==placement.side,
                  !originalNames.contains(page.sourceName),(record.processingArtifacts ?? []).contains(page.sourceName) else {throw ScanFailure.invalidSource}
            try localSource(url,job:job)
            guard try fingerprint(url,isCancelled:isCancelled,onCheckpoint:onCheckpoint).2==result.digest else {throw ScanFailure.invalidSource}
            let image=try JPEGInput.decode(url)
            guard image.width==page.width,image.height==page.height else {throw ScanFailure.invalidSource}
        }
        var manifest=original;manifest.pages=processed.pages.map(\.page)
        return manifest
    }
    func prepareDocuments(job:ScanJob,analyze:(URL)throws->[OrientationEvidence],referenceAnalyze:(URL,Data)throws->[ReferenceEvidence],
                          detect:((URL)throws->[DocumentRegion])?,onProgress:(Int)throws->Void,isCancelled:()->Bool,onCheckpoint:()throws->Void) throws {
        try processingCheckpoint(isCancelled,onCheckpoint)
        var record=try record(job)
        if try checkedDocuments(record,job:job,isCancelled:isCancelled,onCheckpoint:onCheckpoint) != nil {return}
        guard let profile=job.settings.activeProfile,let manifest=record.manifest,manifest.endReason != nil,!manifest.pages.isEmpty,
              record.processing==nil,(record.receipts ?? []).isEmpty else {throw ScanFailure.unfinishedPages}
        try profile.validateForCapture()
        var sources:[DocumentSourceRecord]=[]
        for raw in manifest.pages {
            let input=job.directory.appendingPathComponent(raw.sourceName)
            try localSource(input,job:job)
            let image=try JPEGInput.decode(input)
            guard image.width==raw.width,image.height==raw.height else {throw ScanFailure.invalidSource}
            let digest=try fingerprint(input,isCancelled:isCancelled,onCheckpoint:onCheckpoint).2
            let regions=try DocumentDetection.select(detect.map {try $0(input)} ?? DocumentDetection.detect(input,isCancelled:isCancelled,onCheckpoint:onCheckpoint))
            guard !regions.isEmpty else {throw DocumentDetectionFailure.unavailable}
            sources.append(DocumentSourceRecord(index:raw.index,name:raw.sourceName,digest:digest,regions:regions))
        }
        let placements=try documentPlacements(sources,manifest:manifest)
        var results:[ProcessedDocumentPage]=[],notices=Set<OrientationNotice>()
        func reserve(_ prefix:String)throws->URL {
            let name=prefix+UUID().uuidString+".jpg"
            if record.processingArtifacts==nil {record.processingArtifacts=[]}
            record.processingArtifacts!.append(name)
            try write(record,to:job.directory.appendingPathComponent("job.json"))
            return job.directory.appendingPathComponent(name)
        }
        for placement in placements {
            try autoreleasepool {
                try processingCheckpoint(isCancelled,onCheckpoint)
                let source=sources[placement.sourceIndex-1],input=job.directory.appendingPathComponent(source.name)
                let cropped=try reserve("document-crop-")
                try DocumentDetection.write(input:input,region:source.regions[placement.regionIndex],output:cropped,isCancelled:isCancelled,onCheckpoint:onCheckpoint)
                let fallback=placement.side == .front ? profile.frontRotation:profile.backRotation
                var angle=fallback
                if profile.orientation == .vision {
                    let empty=[0,90,180,270].map {OrientationEvidence(rotation:$0,score:0,lines:0)}
                    let evidence=try? analyze(cropped)
                    var decision=OrientationDecision.resolve(front:evidence ?? empty,back:nil,mapping:nil,fallbackFront:fallback,fallbackBack:0)
                    if evidence==nil {decision=OrientationResult(front:fallback,back:nil,notice:.unavailable)}
                    try processingCheckpoint(isCancelled,onCheckpoint)
                    if let reference=profile.referencePrint {
                        if let referenceEvidence=try? referenceAnalyze(cropped,reference) {
                            decision=ReferenceDecision.resolve(text:decision,front:referenceEvidence,back:nil,mapping:nil,
                                fallbackFront:fallback,fallbackBack:0,printedOffset:0,ocrFront:evidence ?? [],ocrBack:[])
                        } else if decision.notice == .uncertain {decision=OrientationResult(front:fallback,back:nil,notice:.unavailable)}
                    }
                    angle=decision.front;if let notice=decision.notice {notices.insert(notice)}
                }
                try processingCheckpoint(isCancelled,onCheckpoint)
                let output=try reserve("document-")
                try PageRotation.write(input:cropped,output:output,degrees:angle)
                let image=try JPEGInput.decode(output)
                let page=ValidatedPage(index:results.count+1,sheet:placement.sheet,side:placement.side,sourceName:output.lastPathComponent,width:image.width,height:image.height)
                results.append(ProcessedDocumentPage(sourceIndex:placement.sourceIndex,regionIndex:placement.regionIndex,page:page,
                    digest:try fingerprint(output,isCancelled:isCancelled,onCheckpoint:onCheckpoint).2))
                try onProgress(results.count)
            }
        }
        record.documentProcessing=DocumentProcessingRecord(revision:1,sources:sources,pages:results,notices:notices.sorted {$0.rawValue<$1.rawValue})
        try processingCheckpoint(isCancelled,onCheckpoint)
        try write(record,to:job.directory.appendingPathComponent("job.json"))
        _ = try checkedDocuments(record,job:job,isCancelled:isCancelled,onCheckpoint:onCheckpoint)
    }
}
