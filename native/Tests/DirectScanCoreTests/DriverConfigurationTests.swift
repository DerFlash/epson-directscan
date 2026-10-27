import Testing
@testable import DirectScanCore

@Suite struct DriverConfigurationTests {
    @Test func enabledCorrectionsMustExistAndMatchReadback() throws {
        let settings = ScanSettings()
        try validateDriverCorrections(settings: settings, actual: ["VF_AUTOCROP": 1, "VF_DESKEW": 1, "VF_AUTOROTATE": 1])
        #expect(throws: (any Error).self) { try validateDriverCorrections(settings: settings, actual: ["VF_AUTOCROP": 1, "VF_DESKEW": 1]) }
        #expect(throws: (any Error).self) { try validateDriverCorrections(settings: settings, actual: ["VF_AUTOCROP": 1, "VF_DESKEW": 1, "VF_AUTOROTATE": 0]) }
        #expect(throws: (any Error).self) { try validateDriverCorrections(settings: settings, actual: ["VF_AUTOCROP": 2, "VF_DESKEW": 1, "VF_AUTOROTATE": 1]) }
    }
    @Test func disabledCorrectionsMayBeUnavailableButCannotStayEnabled() throws {
        var settings = ScanSettings(); settings.crop = false; settings.deskew = false; settings.rotate = false
        try validateDriverCorrections(settings: settings, actual: [:])
        try validateDriverCorrections(settings: settings, actual: ["VF_AUTOCROP": 0, "VF_DESKEW": 0, "VF_AUTOROTATE": 0])
        #expect(throws: (any Error).self) { try validateDriverCorrections(settings: settings, actual: ["VF_AUTOROTATE": 1]) }
    }
}
