import Foundation

/// The choices restored together with a profile, independent of its image geometry.
public struct ProfileScanSettings: Codable, Equatable {
    public var destination: String?
    public var outputFormat: OutputFormat
    public var duplex: Bool
    public var automaticFeeding: Bool
    public var feedingTimeoutSeconds: Int
    public var crop: Bool
    public var deskew: Bool
    public var rotate: Bool

    public init(settings: ScanSettings) {
        destination = settings.destination; outputFormat = settings.outputFormat
        duplex = settings.duplex; automaticFeeding = settings.automaticFeeding
        feedingTimeoutSeconds = settings.feedingTimeoutSeconds
        crop = settings.crop; deskew = settings.deskew; rotate = settings.rotate
    }

    public func validate() throws {
        guard destination == nil || destination!.hasPrefix("/"),
              [0, 30, 60, 120, 300].contains(feedingTimeoutSeconds) else { throw ScanFailure.invalidSettings }
    }

    public func apply(to settings: inout ScanSettings) {
        settings.destination = destination; settings.outputFormat = outputFormat
        settings.duplex = duplex; settings.automaticFeeding = automaticFeeding
        settings.feedingTimeoutSeconds = feedingTimeoutSeconds
        settings.crop = crop; settings.deskew = deskew; settings.rotate = rotate
    }
}

extension ScanSettings {
    public mutating func saveProfile(_ profile: ScanProfile) throws {
        try profile.validateForCapture()
        var next = self
        next.rememberActiveProfileSettings()
        if let index = next.profiles.firstIndex(where: { $0.id == profile.id }) {
            next.profiles[index] = profile
        } else { next.profiles.append(profile) }
        next.activeProfileID = profile.id
        profile.scanSettings?.apply(to: &next)
        next.rememberActiveProfileSettings()
        try next.validate()
        self = next
    }

    public mutating func removeProfile(_ id: UUID) throws {
        var next = self
        if next.activeProfileID == id { try next.selectProfile(nil) }
        next.profiles.removeAll { $0.id == id }
        try next.validate()
        self = next
    }

    public mutating func rememberActiveProfileSettings() {
        let saved = ProfileScanSettings(settings: self)
        // Schema-3 upgrades may already have a named profile active. Preserve
        // their original live choices for the legacy entry before first switching.
        if legacyScanSettings == nil { legacyScanSettings = saved }
        if let index = profiles.firstIndex(where: { $0.id == activeProfileID }) {
            profiles[index].scanSettings = saved
        } else if activeProfileID == nil {
            legacyScanSettings = saved
        }
    }

    public mutating func selectProfile(_ id: UUID?) throws {
        guard id == nil || profiles.contains(where: { $0.id == id }) else { throw ScanFailure.invalidSettings }
        let target = id.flatMap { selected in profiles.first { $0.id == selected } }
        try target?.validateForCapture()
        // Validate before saving the old profile or changing any live choice.
        if id == nil { try legacyScanSettings?.validate() }
        if activeProfileID == id { rememberActiveProfileSettings(); return }
        rememberActiveProfileSettings()
        activeProfileID = id
        (target?.scanSettings ?? (id == nil ? legacyScanSettings : nil))?.apply(to: &self)
        // Historical profiles without saved choices inherit the current values once.
        rememberActiveProfileSettings()
    }
}
