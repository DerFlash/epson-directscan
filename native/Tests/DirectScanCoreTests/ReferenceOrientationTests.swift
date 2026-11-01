import Foundation
import Testing
@testable import DirectScanCore

@Suite struct ReferenceOrientationTests {
    private let mapping=DuplexMapping(sign:-1,offset:0)
    @Test func individualStrongOCRCannotBeHiddenByUncertainPairScores() {
        let strong=[0,90,180,270].map{OrientationEvidence(rotation:$0,score:$0==0 ? 20:0,lines:$0==0 ? 2:0)}
        let weak=zip([0,90,180,270],[0.0,17,18,17]).map{OrientationEvidence(rotation:$0.0,score:$0.1,lines:$0.1>0 ? 1:0)}
        for swapped in [false,true] {
            let a=swapped ? weak:strong,b=swapped ? strong:weak
            let text=OrientationDecision.resolve(front:a,back:b,mapping:mapping,fallbackFront:0,fallbackBack:0)
            #expect(text.notice == .uncertain)
            let result=ReferenceDecision.resolve(text:text,front:swapped ? match(180):match(nil),back:swapped ? match(nil):match(180),mapping:mapping,fallbackFront:0,fallbackBack:0,ocrFront:a,ocrBack:b)
            #expect(result.front==0 && result.back==0 && result.notice == .conflict)
        }
    }
    private func match(_ angle:Int?,best:Double=5,next:Double=20)->[ReferenceEvidence] {
        [0,90,180,270].map{ReferenceEvidence(rotation:$0,distance:$0 == angle ? best:next)}
    }
    private func decide(_ a:[ReferenceEvidence],_ b:[ReferenceEvidence]?,text:OrientationResult?=nil)->OrientationResult {
        ReferenceDecision.resolve(text:text ?? OrientationResult(front:0,back:b == nil ? nil:0,notice:.uncertain),front:a,back:b,mapping:mapping,fallbackFront:180,fallbackBack:180)
    }
    @Test func textPoorEnergyUsesMatchingBackWhicheverPhysicalChannelCarriesIt() {
        let back=decide(match(nil),match(90))
        #expect(back.front==270 && back.back==90 && back.notice==nil)
        let front=decide(match(90),match(nil))
        #expect(front.front==90 && front.back==270 && front.notice==nil)
        let unavailable=decide(match(nil),match(90),text:OrientationResult(front:0,back:0,notice:.unavailable))
        #expect(unavailable.front==270 && unavailable.back==90 && unavailable.notice==nil)
    }
    @Test func unrelatedNearTieAndInvalidDistancesKeepConservativeFallback() {
        let tie=[ReferenceEvidence(rotation:0,distance:10),ReferenceEvidence(rotation:90,distance:11),ReferenceEvidence(rotation:180,distance:20),ReferenceEvidence(rotation:270,distance:22)]
        for bad in [match(90,best:13),tie,match(nil),match(90,best:Double.nan),match(90,best:-1),Array(match(90).prefix(3))] {
            let result=decide(bad,match(nil))
            #expect(result.front==0 && result.back==0 && result.notice == .uncertain)
        }
    }
    @Test func strongOCRAndTwoReferenceChannelsCannotDisagreeSilently() {
        let text=OrientationResult(front:0,back:0,notice:nil)
        let conflict=decide(match(nil),match(90),text:text)
        #expect(conflict.front==180 && conflict.back==180 && conflict.notice == .conflict)
        let pair=decide(match(90),match(90))
        #expect(pair.front==180 && pair.back==180 && pair.notice == .conflict)
        let reliable=decide(match(nil),match(nil),text:text)
        #expect(reliable.front==0 && reliable.back==0 && reliable.notice==nil)
    }
    @Test func calibratedOffsetsAndSinglePagesResolveButMissingPairsStayVisible() {
        let result=ReferenceDecision.resolve(text:OrientationResult(front:0,back:0,notice:.uncertain),front:match(nil),back:match(90),mapping:mapping,fallbackFront:0,fallbackBack:0,printedOffset:180)
        #expect(result.front==90 && result.back==90 && result.notice==nil)
        let single=decide(match(270),nil)
        #expect(single.front==270 && single.back==nil && single.notice==nil)
        let missing=decide(match(90),nil,text:OrientationResult(front:0,back:nil,notice:.missingPair))
        #expect(missing.notice == .missingPair)
    }
}
