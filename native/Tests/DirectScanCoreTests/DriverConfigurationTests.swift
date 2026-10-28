import Testing
import Foundation
@testable import EpsonDirectScan
@testable import DirectScanCore

@Suite struct DriverConfigurationTests {
    @Test func activeProfileRequiresExplicitDisabledCorrectionReadbacks() throws {
        var s=ScanSettings();var p=ScanProfile(name:"Hülle");p.area=ScanArea(widthMM:76,heightMM:102);p.orientation = .vision
        s.profiles=[p];s.activeProfileID=p.id
        for actual in [["VF_DESKEW":0],["VF_DESKEW":0,"VF_AUTOCROP":0],["VF_DESKEW":0,"VF_AUTOROTATE":0],["VF_AUTOCROP":0,"VF_AUTOROTATE":0], ["VF_DESKEW":1,"VF_AUTOCROP":0,"VF_AUTOROTATE":0]] {
            #expect(throws:(any Error).self) {try validateDriverCorrections(settings:s,actual:actual)}
        }
        try validateDriverCorrections(settings:s,actual:["VF_DESKEW":0,"VF_AUTOCROP":0,"VF_AUTOROTATE":0])
    }
    @Test func profileDisablesConflictingDriverCorrectionsInBothPayloads() throws {
        var s = ScanSettings();var p = ScanProfile(name:"Hülle")
        p.area = ScanArea(widthMM:76,heightMM:102);p.orientation = .vision
        s.profiles = [p];s.activeProfileID = p.id
        try validateDriverCorrections(settings:s,actual:["VF_AUTOCROP":0,"VF_DESKEW":0,"VF_AUTOROTATE":0])
        let bytes = try NativeProcess.feedingPayload(s)
        let payload = try #require(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        #expect(payload["crop"] as? Bool == false && payload["rotate"] as? Bool == false)
        #expect(payload["deskew"] as? Bool == false)
        #expect(payload["profileWidthMM"] as? Double == 76 && payload["profileHeightMM"] as? Double == 102)
        #expect(s.deskew)
        s.activeProfileID=nil
        let legacy=try #require(JSONSerialization.jsonObject(with:NativeProcess.feedingPayload(s)) as? [String:Any])
        #expect(legacy["deskew"] as? Bool == true)
    }
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
