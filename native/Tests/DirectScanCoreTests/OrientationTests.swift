import Testing
@testable import DirectScanCore

@Suite struct OrientationTests {
    func evidence(_ angle: Int?) -> [OrientationEvidence] {
        [0,90,180,270].map { OrientationEvidence(rotation:$0,score:$0 == angle ? 60 : 0,lines:$0 == angle ? 4 : 0) }
    }
    @Test func readableSideMayBeEitherChannelWithEitherSensorDirection() {
        for (sign,offset,wantB) in [(1,0,90),(-1,0,270),(1,180,270),(-1,180,90)] {
            let mapping = DuplexMapping(sign:sign,offset:offset)
            let a = OrientationDecision.resolve(front:evidence(90),back:evidence(nil),mapping:mapping,fallbackFront:0,fallbackBack:180)
            #expect(a.front == 90 && a.back == wantB && a.notice == nil)
            let b = OrientationDecision.resolve(front:evidence(nil),back:evidence(wantB),mapping:mapping,fallbackFront:0,fallbackBack:180)
            #expect(b.front == 90 && b.back == wantB && b.notice == nil)
        }
    }
    @Test func uncertainUncalibratedOrContradictoryPairsUseBothFallbacks() {
        let uncalibrated = OrientationDecision.resolve(front:evidence(90),back:evidence(nil),mapping:nil,fallbackFront:180,fallbackBack:90)
        #expect(uncalibrated.front == 180 && uncalibrated.back == 90 && uncalibrated.notice == .uncalibrated)
        let empty = OrientationDecision.resolve(front:evidence(nil),back:evidence(nil),mapping:DuplexMapping(sign:1,offset:0),fallbackFront:180,fallbackBack:90)
        #expect(empty.front == 180 && empty.back == 90 && empty.notice == .uncertain)
        let conflict = OrientationDecision.resolve(front:evidence(90),back:evidence(180),mapping:DuplexMapping(sign:1,offset:0),fallbackFront:180,fallbackBack:90)
        #expect(conflict.front == 180 && conflict.back == 90 && conflict.notice == .conflict)
        let tied = [0,90,180,270].map { OrientationEvidence(rotation:$0,score:60,lines:4) }
        #expect(OrientationDecision.resolve(front:tied,back:nil,mapping:nil,fallbackFront:270,fallbackBack:0).front == 270)
    }
    @Test func invalidEvidenceCannotBecomeAnAutomaticRotation() {
        let malformed = [OrientationEvidence(rotation:90,score:.infinity,lines:5)]
        let result = OrientationDecision.resolve(front:malformed,back:nil,mapping:nil,fallbackFront:180,fallbackBack:0)
        #expect(result.front == 180 && result.notice != nil)
    }
}
