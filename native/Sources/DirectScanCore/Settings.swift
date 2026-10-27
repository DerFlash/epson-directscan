import Foundation

public enum OutputFormat: String, Codable { case jpg, pdf }

public struct ScanSettings: Codable, Equatable {
    public var schemaVersion = 2
    public var destination: String?
    public var paused = false
    public var crop = true
    public var deskew = true
    public var rotate = true
    public var duplex = false
    public var outputFormat: OutputFormat = .jpg
    public var automaticFeeding = false
    public var feedingTimeoutSeconds = 120
    public init(destination: String? = nil) { self.destination = destination }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, destination, paused, crop, deskew, rotate, duplex, outputFormat, automaticFeeding, feedingTimeoutSeconds
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard [1,2].contains(version) else { throw ScanFailure.invalidSettings }
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        paused = try c.decode(Bool.self, forKey: .paused)
        crop = try c.decode(Bool.self, forKey: .crop)
        deskew = try c.decode(Bool.self, forKey: .deskew)
        rotate = try c.decode(Bool.self, forKey: .rotate)
        if version == 2 {
            duplex = try c.decode(Bool.self, forKey: .duplex)
            outputFormat = try c.decode(OutputFormat.self, forKey: .outputFormat)
            automaticFeeding = try c.decode(Bool.self, forKey: .automaticFeeding)
            feedingTimeoutSeconds = try c.decode(Int.self, forKey: .feedingTimeoutSeconds)
        }
        try validate()
    }
    public func validate() throws {
        guard schemaVersion == 2, destination == nil || destination!.hasPrefix("/"),
              [0,30,60,120,300].contains(feedingTimeoutSeconds) else {
            throw ScanFailure.invalidSettings
        }
    }
}

public enum ScanFailure: String, Error, LocalizedError {
    case invalidSettings, invalidDestination, invalidJPEG, invalidSource, collision, unfinishedPages, invalidPDF, incompletePair
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: return "Die Einstellungen konnten nicht gelesen werden. Bitte die Einstellungen prüfen."
        case .invalidDestination: return "Der Ablageordner fehlt oder ist nicht beschreibbar. Bitte einen Ordner wählen."
        case .invalidJPEG: return "Ein Scan ist unvollständig oder kein lesbares JPG. Er bleibt zur Prüfung erhalten."
        case .invalidSource: return "Der Treiber hat eine unerwartete Scandatei gemeldet. Der Vorgang wurde angehalten."
        case .collision: return "Eine Zieldatei existiert bereits. Es wurde nichts überschrieben."
        case .unfinishedPages: return "Es gibt unbestätigte Scans. Bitte die zurückgehaltenen Dateien prüfen."
        case .invalidPDF: return "Das PDF konnte nicht vollständig geprüft werden. Die gescannten Seiten bleiben erhalten."
        case .incompletePair: return "Zu einer Karte fehlt eine Seite. Die vorhandenen Seiten bleiben erhalten."
        }
    }
}
