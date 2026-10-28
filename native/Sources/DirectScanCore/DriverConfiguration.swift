import Foundation

public enum DriverConfigurationFailure: Error, LocalizedError {
    case unavailable, rejected
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Der Treiber konnte die benötigten Bildkorrekturen nicht bestätigen."
        case .rejected: return "Der Treiber hat die Bildkorrekturen nicht bestätigt. Es wurde kein Scan gestartet."
        }
    }
}

public func validateDriverCorrections(settings: ScanSettings, actual: [String: Int]) throws {
    let expected = ["VF_AUTOCROP": settings.driverCrop ? 1 : 0,
                    "VF_DESKEW": settings.driverDeskew ? 1 : 0,
                    "VF_AUTOROTATE": settings.driverRotate ? 1 : 0]
    for (key, value) in expected {
        guard let readback = actual[key] else {
            let profileNeedsConfirmation = settings.activeProfile.map {
                key == "VF_AUTOROTATE" || (["VF_AUTOCROP","VF_DESKEW"].contains(key) && !$0.area.isAutomatic)
            } ?? false
            if value != 0 || profileNeedsConfirmation { throw DriverConfigurationFailure.unavailable }
            continue
        }
        guard readback == value else { throw DriverConfigurationFailure.rejected }
    }
}
