import Testing
@testable import EpsonDirectScan

@Suite @MainActor struct ShutdownTests {
    @Test func saveIntentSurvivesProgressBeyondThirtySecondsAndEndsOnWorkerExit() {
        var running=true,replies:[Bool]=[],delayed:[(Double,()->Void)]=[]
        let flow=ShutdownFlow(workerRunning:{running},pause:{},save:{},reply:{replies.append($0)},schedule:{delayed.append(($0,$1))})
        #expect(flow.requestSave())
        // Execute every scheduled callback that could have fired over two minutes.
        // Saving must keep its intent while the worker is making progress.
        for (_,task) in delayed.filter({$0.0 <= 120}) {task()}
        flow.changed()
        #expect(flow.waiting && replies.isEmpty)
        running=false;flow.changed()
        #expect(!flow.waiting && replies == [false])
        flow.changed();#expect(replies.count == 1)
    }
    @Test func ordinaryPauseStillHasABoundedForcedExit() {
        var replies:[Bool]=[],delayed:[(Double,()->Void)]=[]
        let flow=ShutdownFlow(workerRunning:{true},pause:{},save:{},reply:{replies.append($0)},schedule:{delayed.append(($0,$1))})
        #expect(flow.requestPause())
        for (_,task) in delayed.filter({$0.0 <= 5}) {task()}
        #expect(flow.waiting && replies.isEmpty)
        for (_,task) in delayed.filter({$0.0 <= 6}) {task()}
        #expect(!flow.waiting && replies == [true])
    }
    @Test func failedOrAlreadyExitedWorkerDoesNotLeaveSaveQuitWaitingForever() {
        var running=true,replies:[Bool]=[]
        let flow=ShutdownFlow(workerRunning:{running},pause:{},save:{},reply:{replies.append($0)})
        #expect(flow.requestSave());running=false;flow.changed()
        #expect(replies == [false])
        #expect(!flow.requestPause())
    }
}
