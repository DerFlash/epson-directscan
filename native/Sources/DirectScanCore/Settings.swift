import Foundation

public struct ScanSettings: Codable, Equatable {
    public var schemaVersion = 1
    public var destination: String?
    public var paused = false
    public var crop = true
    public var deskew = true
    public var rotate = true
    public init(destination: String? = nil) { self.destination = destination }
    public func validate() throws {
        guard schemaVersion == 1, destination == nil || destination!.hasPrefix("/") else {
            throw ScanFailure.invalidSettings
        }
    }
}

public enum ScanFailure: String, Error, LocalizedError {
    case invalidSettings, invalidDestination, invalidJPEG, invalidSource, collision, unfinishedPages
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: return "Die Einstellungen konnten nicht gelesen werden. Bitte die Einstellungen prüfen."
        case .invalidDestination: return "Der Ablageordner fehlt oder ist nicht beschreibbar. Bitte einen Ordner wählen."
        case .invalidJPEG: return "Ein Scan ist unvollständig oder kein lesbares JPG. Er bleibt zur Prüfung erhalten."
        case .invalidSource: return "Der Treiber hat eine unerwartete Scandatei gemeldet. Der Vorgang wurde angehalten."
        case .collision: return "Eine Zieldatei existiert bereits. Es wurde nichts überschrieben."
        case .unfinishedPages: return "Es gibt unbestätigte Scans. Bitte die zurückgehaltenen Dateien prüfen."
        }
    }
}
