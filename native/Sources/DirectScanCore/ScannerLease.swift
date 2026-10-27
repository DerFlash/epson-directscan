import Foundation
import Darwin

public enum ScannerLeaseFailure: Error, LocalizedError {
    case occupied
    public var errorDescription: String? {
        "Ein vorheriger Scanprozess hält den Scanner noch. Bitte warten und anschließend neu verbinden. Epson-Dienste bleiben bis zur Freigabe pausiert."
    }
}

// Helpers hold this independently of their parent, including throughout a slow close.
public final class ScannerLease {
    private let descriptor: Int32
    public init(root: URL) throws {
        let path = root.appendingPathComponent("scanner.lock").path
        let fd = Darwin.open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else {
            _ = Darwin.close(fd); throw CocoaError(.fileReadNoPermission)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            _ = Darwin.close(fd); throw ScannerLeaseFailure.occupied
        }
        _ = fchmod(fd, mode_t(0o600))
        descriptor = fd
    }
    deinit { _ = Darwin.close(descriptor) }
}
