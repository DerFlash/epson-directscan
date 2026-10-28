import Foundation
import CoreGraphics
import Testing
@testable import DirectScanCore

@Suite struct ProfileTests {
    @Test func fixedFrameCannotUseDriverRotationBeforeFraming() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination()
        var p=ScanProfile(name:"Hülle");p.area=ScanArea(widthMM:77,heightMM:102);p.orientation = .epson
        var s=ScanSettings(destination:out.path);s.profiles=[p];s.activeProfileID=p.id
        #expect(throws:(any Error).self) {try store.beginJob(settings:s)}
    }
    @Test func historicalFixedDriverRotationProfilesAndPendingJobsStayReadable() throws {
        let f=try StorageTests(),store=try f.store(),out=try f.destination()
        var p=ScanProfile(name:"Altes Hüllenprofil");p.area=ScanArea(widthMM:77,heightMM:102);p.orientation = .epson
        var s=ScanSettings(destination:out.path);s.profiles=[p]
        //Even an inactive historical profile must not reset all preferences.
        let encoded=try JSONEncoder().encode(s)
        try encoded.write(to:store.root.appendingPathComponent("settings.json"))
        #expect(try store.loadSettings() == s)
        let job=try store.beginJob(settings:ScanSettings(destination:out.path))
        let source=job.directory.appendingPathComponent("original.jpg");try f.jpeg(source,width:100,height:200)
        let original=try Data(contentsOf:source)
        try store.stage(source:source,job:job,sheet:1,side:.front);try store.complete(job:job,reason:.completed)
        let record=job.directory.appendingPathComponent("job.json")
        var historical=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:record)) as? [String:Any])
        var savedJob=try #require(historical["job"] as? [String:Any]);s.activeProfileID=p.id
        savedJob["settings"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(s));historical["job"]=savedJob
        try JSONSerialization.data(withJSONObject:historical).write(to:record)
        let retained=try #require(store.pendingJobs().first)
        #expect(retained.settings.activeProfile?.orientation == .epson)
        #expect(throws:(any Error).self) {try store.prepareImages(job:retained)}
        #expect(try Data(contentsOf:source) == original)
    }
    @Test func migrationKeepsLegacyBehaviorAndBacksUpExactSchemaTwoBytes() throws {
        let fixture = try StorageTests(), store = try fixture.store()
        let data = Data(#"{"schemaVersion":2,"destination":"/tmp","paused":true,"crop":false,"deskew":false,"rotate":true,"duplex":true,"outputFormat":"pdf","automaticFeeding":true,"feedingTimeoutSeconds":30}"#.utf8)
        try data.write(to: store.root.appendingPathComponent("settings.json"))
        let settings = try store.loadSettings()
        #expect(settings.schemaVersion == 3)
        #expect(settings.paused && settings.duplex && settings.rotate && !settings.crop)
        #expect(try Data(contentsOf: store.root.appendingPathComponent("settings-v2-backup.json")) == data)
        #expect(try store.loadSettings() == settings)
    }
    @Test func selectedProfileFreezesFlagsAndRoundTrips() throws {
        var s = ScanSettings(destination: "/tmp")
        var p = ScanProfile(name: "Toploader")
        p.area = ScanArea(widthMM: 76, heightMM: 102)
        p.orientation = .vision; p.frontRotation = 90; p.backRotation = 270
        s.profiles = [p]; s.activeProfileID = p.id
        try s.validate()
        #expect(!s.driverCrop && !s.driverRotate && s.requiresImageProcessing)
        #expect(try JSONDecoder().decode(ScanSettings.self, from: JSONEncoder().encode(s)) == s)
        s.activeProfileID = UUID()
        #expect(throws: (any Error).self) { try s.validate() }
        s.activeProfileID = p.id; s.profiles.append(p)
        #expect(throws: (any Error).self) { try s.validate() }
    }
    @Test func dimensionsAreCenteredAndRejectUnsafeValues() throws {
        let area = ScanArea(widthMM: 63, heightMM: 88)
        #expect(try area.rectangle(maximumMM: CGSize(width: 216, height: 297)) == CGRect(x: 76.5, y: 0, width: 63, height: 88))
        for bad in [Double.nan, .infinity, 0, 49, 216] {
            #expect(throws: (any Error).self) { try ScanArea(widthMM: bad, heightMM: 88).validate() }
        }
        #expect(throws: (any Error).self) { try ScanArea(widthMM: 63, heightMM: nil).rectangle(maximumMM: CGSize(width:216,height:297)) }
        #expect(throws: (any Error).self) { try area.rectangle(maximumMM: CGSize(width:60,height:297)) }
    }
}
