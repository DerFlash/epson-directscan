import AppKit
import DirectScanCore
import Darwin

@main
enum DirectScanMain {
    static func main() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Epson DirectScan", isDirectory: true)
        do {
            let storage = try ScanStorage(root: base)
            let lockFD = Darwin.open(base.appendingPathComponent("instance.lock").path, O_RDWR | O_CREAT, mode_t(0o600))
            guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate(storage: storage)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            _ = close(lockFD)
        } catch {
            let alert = NSAlert(); alert.messageText = "DirectScan kann nicht starten"; alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK"); alert.runModal(); exit(1)
        }
    }
}
