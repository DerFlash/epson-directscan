import Foundation

func processingCheckpoint(_ isCancelled: () -> Bool, _ onCheckpoint: () throws -> Void) throws {
    guard !isCancelled() else { throw CocoaError(.userCancelled) }
    try onCheckpoint()
    guard !isCancelled() else { throw CocoaError(.userCancelled) }
}

struct ProcessedPage: Codable {
    let originalName: String
    let originalDigest: String
    let page: ValidatedPage
    let digest: String
}
struct ProcessingRecord: Codable {
    let pages: [ProcessedPage]
    let notices: [OrientationNotice]
}

extension ScanStorage {
    public func processingNotice(job: ScanJob) throws -> [OrientationNotice] { try record(job).processing?.notices ?? [] }

    func checkedProcessing(_ record: JobRecord, job: ScanJob, isCancelled: () -> Bool = {false}, onCheckpoint: () throws -> Void = {}) throws -> PageManifest? {
        guard let processed = record.processing, let original = record.manifest,
              processed.pages.count == original.pages.count else {
            if record.processing != nil { throw ScanFailure.invalidSource };return nil
        }
        for (p,raw) in zip(processed.pages,original.pages) {
            try processingCheckpoint(isCancelled,onCheckpoint)
            let source = job.directory.appendingPathComponent(p.originalName), output = job.directory.appendingPathComponent(p.page.sourceName)
            try localSource(source,job:job);try localSource(output,job:job)
            guard p.originalName == raw.sourceName, p.page.index == raw.index, p.page.sheet == raw.sheet, p.page.side == raw.side,
                  (record.processingArtifacts ?? []).contains(p.page.sourceName),
                  try fingerprint(source,isCancelled:isCancelled,onCheckpoint:onCheckpoint).2 == p.originalDigest,
                  try fingerprint(output,isCancelled:isCancelled,onCheckpoint:onCheckpoint).2 == p.digest else { throw ScanFailure.invalidSource }
            let image = try JPEGInput.decode(output)
            guard image.width == p.page.width, image.height == p.page.height else { throw ScanFailure.invalidSource }
        }
        var manifest = original;manifest.pages = processed.pages.map(\.page);return manifest
    }

    public func prepareImages(job: ScanJob, analyze: (URL) throws -> [OrientationEvidence] = VisionOrientation.analyze,
                              onProgress: (Int) throws -> Void = { _ in }, isCancelled: () -> Bool = { false }, onCheckpoint: () throws -> Void = {}) throws {
        try processingCheckpoint(isCancelled,onCheckpoint)
        guard job.settings.requiresImageProcessing, let profile = job.settings.activeProfile else { return }
        var record = try record(job)
        if try checkedProcessing(record,job:job,isCancelled:isCancelled,onCheckpoint:onCheckpoint) != nil { return }
        guard let manifest = record.manifest, manifest.endReason != nil, !manifest.pages.isEmpty,
              (record.receipts ?? []).isEmpty else { throw ScanFailure.unfinishedPages }
        var results: [ProcessedPage] = [], notices: Set<OrientationNotice> = []
        let groups = Dictionary(grouping:manifest.pages,by:\.sheet).sorted { $0.key < $1.key }
        for (_,group) in groups {
            try autoreleasepool {
                guard !isCancelled() else { throw CocoaError(.userCancelled) }
                for raw in group {
                    try processingCheckpoint(isCancelled,onCheckpoint)
                    let source = job.directory.appendingPathComponent(raw.sourceName)
                    try localSource(source,job:job)
                    let image = try JPEGInput.decode(source)
                    guard image.width == raw.width, image.height == raw.height else { throw ScanFailure.invalidSource }
                }
                let front = group.first { $0.side == .front }, back = group.first { $0.side == .back }
                var angles: [PageSide:Int] = [.front:profile.frontRotation,.back:profile.backRotation]
                if profile.orientation == .vision {
                    let mapping = job.settings.automaticFeeding ? profile.feedingMapping : profile.icaMapping
                    if job.settings.duplex && (front == nil || back == nil) { notices.insert(.missingPair) }
                    else if job.settings.duplex && mapping == nil { notices.insert(.uncalibrated) }
                    else if let front {
                        do {
                            let a = try analyze(job.directory.appendingPathComponent(front.sourceName))
                            guard !isCancelled() else { throw CocoaError(.userCancelled) }
                            let b = try back.map { try analyze(job.directory.appendingPathComponent($0.sourceName)) }
                            let decision = OrientationDecision.resolve(front:a,back:b,mapping:mapping,
                                fallbackFront:profile.frontRotation,fallbackBack:profile.backRotation,printedOffset:profile.printedBackOffset)
                            angles[.front] = decision.front;angles[.back] = decision.back ?? profile.backRotation
                            if let notice = decision.notice { notices.insert(notice) }
                        } catch { notices.insert(.unavailable) }
                    }
                }
                for raw in group {
                    guard !isCancelled() else { throw CocoaError(.userCancelled) }
                    let source = job.directory.appendingPathComponent(raw.sourceName)
                    try localSource(source,job:job)
                    let originalDigest = try fingerprint(source,isCancelled:isCancelled,onCheckpoint:onCheckpoint).2
                    let name = "processed-"+UUID().uuidString+".jpg", output = job.directory.appendingPathComponent(name)
                    // Reserve ownership before creating any output. Interrupted copies are
                    // safe to retain until verified export, without mistaking them for originals.
                    if record.processingArtifacts == nil { record.processingArtifacts = [] }
                    record.processingArtifacts!.append(name)
                    try write(record,to:job.directory.appendingPathComponent("job.json"))
                    try PageRotation.write(input:source,output:output,degrees:angles[raw.side]!)
                    let image = try JPEGInput.decode(output)
                    let page = ValidatedPage(index:raw.index,sheet:raw.sheet,side:raw.side,sourceName:name,width:image.width,height:image.height)
                    results.append(ProcessedPage(originalName:raw.sourceName,originalDigest:originalDigest,page:page,digest:try fingerprint(output,isCancelled:isCancelled,onCheckpoint:onCheckpoint).2))
                }
                try onProgress(results.count)
            }
        }
        results.sort { $0.page.index < $1.page.index }
        guard !isCancelled() else { throw CocoaError(.userCancelled) }
        record.processing = ProcessingRecord(pages:results,notices:notices.sorted { $0.rawValue < $1.rawValue })
        try write(record,to:job.directory.appendingPathComponent("job.json"))
        _ = try checkedProcessing(record,job:job,isCancelled:isCancelled,onCheckpoint:onCheckpoint)
    }
}
