import Testing
@testable import DirectScanCore

@Suite struct PolicyTests {
    @Test func testOnlyReadyAcceptsOneButtonAndBusyEventsAreDropped() {
        var p = ScanPolicy()
        let accepted1 = p.buttonPressed(); #expect(!accepted1)
        p.resume()
        let accepted2 = p.buttonPressed(); #expect(!accepted2)
        p.sessionReady()
        let accepted3 = p.buttonPressed(); #expect(accepted3)
        let accepted4 = p.buttonPressed(); #expect(!accepted4)
        let accepted5 = p.buttonPressed(); #expect(!accepted5)
        p.completed()
        #expect(p.phase == .ready)
        let accepted6 = p.buttonPressed(); #expect(accepted6)
    }
    @Test func testDisconnectAndFailureNeverReplayButton() {
        var p = ScanPolicy()
        p.resume(); p.sessionReady(); let accepted7 = p.buttonPressed(); #expect(accepted7)
        p.disconnected()
        #expect(p.phase == .error)
        p.sessionReady()
        let accepted8 = p.buttonPressed(); #expect(!accepted8)
        p.recover(); p.sessionReady()
        #expect(p.phase == .ready)
        p.failed(); p.sessionReady()
        let accepted9 = p.buttonPressed(); #expect(!accepted9)
    }
    @Test func testPausedAndIdleReconnectNeverScanAutomatically() {
        var p = ScanPolicy()
        p.resume(); p.sessionReady(); p.pause(); p.sessionReady()
        #expect(p.phase == .paused)
        let accepted10 = p.buttonPressed(); #expect(!accepted10)
        p.resume(); p.sessionReady(); p.disconnected()
        #expect(p.phase == .searching)
        p.sessionReady()
        #expect(p.phase == .ready)
    }
}
