import Foundation

public enum DriverConfigurationFailure: Error, LocalizedError {
    case unavailable, rejected
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Der Treiber bietet eine eingeschaltete Bildkorrektur nicht an."
        case .rejected: return "Der Treiber hat die Bildkorrekturen nicht bestätigt. Es wurde kein Scan gestartet."
        }
    }
}

public func validateDriverCorrections(settings: ScanSettings, actual: [String: Int]) throws {
    let expected = ["VF_AUTOCROP": settings.crop ? 1 : 0,
                    "VF_DESKEW": settings.deskew ? 1 : 0,
                    "VF_AUTOROTATE": settings.rotate ? 1 : 0]
    for (key, value) in expected {
        guard let readback = actual[key] else {
            if value != 0 { throw DriverConfigurationFailure.unavailable }
            continue
        }
        guard readback == value else { throw DriverConfigurationFailure.rejected }
    }
}
