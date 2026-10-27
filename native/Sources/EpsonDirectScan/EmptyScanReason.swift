enum EmptyScanReason: Int {
    case noPaper = 0, noImages = 1, noProgress = 2, cancelled = 3

    var message: String {
        switch self {
        case .noPaper: return "Keine Vorlage erkannt – Einzug prüfen"
        case .noImages: return "Keine Seite gescannt – Vorlage und Einzug prüfen"
        case .noProgress: return "Einzug ohne Fortschritt beendet – Vorlage prüfen"
        case .cancelled: return "Scan gestoppt – keine Seite gescannt"
        }
    }
}
