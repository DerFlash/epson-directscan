public enum ScanPhase: String { case paused, searching, ready, scanning, error }

public struct ScanPolicy {
    public private(set) var phase: ScanPhase = .paused
    public init() {}
    public mutating func resume() { if phase == .paused { phase = .searching } }
    public mutating func recover() { if phase == .error { phase = .searching } }
    public mutating func sessionReady() { if phase == .searching { phase = .ready } }
    public mutating func buttonPressed() -> Bool {
        guard phase == .ready else { return false }
        phase = .scanning
        return true
    }
    public mutating func completed() { if phase == .scanning { phase = .ready } }
    public mutating func failed() { phase = .error }
    public mutating func disconnected() {
        if phase == .scanning { phase = .error }
        else if phase == .ready { phase = .searching }
    }
    public mutating func pause() { phase = .paused }
}
