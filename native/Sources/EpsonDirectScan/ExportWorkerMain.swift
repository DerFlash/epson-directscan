import Foundation
import DirectScanCore
import Darwin

enum ExportWorkerMain {
    static func run(_ arguments: [String], emit: (HelperEvent) -> Void = { event in
        if let data = try? JSONEncoder().encode(event) { try? FileHandle.standardOutput.write(contentsOf:data+Data([10])) }
    }) -> Int32 {
        guard arguments.count == 5, arguments[2].hasPrefix("/"),
              let id = UUID(uuidString:arguments[3]), let parent = Int32(arguments[4]), parent > 1, parent == getppid() else { return 2 }
        do {
            let storage = try ScanStorage(root:URL(fileURLWithPath:arguments[2],isDirectory:true))
            let lease = try ScannerLease(root:storage.root)
            defer { withExtendedLifetime(lease) {} }
            do {
                guard let job = try storage.pendingJobs().first(where:{ $0.id == id }), job.settings.requiresImageProcessing else { throw ScanFailure.invalidSource }
                try storage.prepareImages(job:job,onProgress:{ count in
                    guard getppid() == parent else { throw CocoaError(.userCancelled) }
                    emit(HelperEvent(event:"processing",value:count))
                })
                guard getppid() == parent else { throw CocoaError(.userCancelled) }
                if try !storage.processingNotice(job:job).isEmpty { emit(HelperEvent(event:"notice",value:1)) }
                let outputs = try storage.export(job:job)
                try storage.finish(job:job)
                for (i,file) in outputs.enumerated() { emit(HelperEvent(event:"file",value:i+1,file:file.lastPathComponent)) }
                emit(HelperEvent(event:"complete",value:outputs.count));emit(HelperEvent(event:"closed",value:0));return 0
            } catch {
                emit(HelperEvent(event:"error",value:-401));emit(HelperEvent(event:"closed",value:0));return 1
            }
        } catch { emit(HelperEvent(event:"error",value:-402));return 1 }
    }
}
