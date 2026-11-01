import Foundation

/// Save intent waits for the supervised worker; ordinary pause retains its
/// short bounded quit. The coordinator already detects stalled save workers.
final class ShutdownFlow {
    private let workerRunning: () -> Bool
    private let pause: () -> Void
    private let save: () -> Void
    private let reply: (Bool) -> Void
    private let schedule: (Double,@escaping () -> Void) -> Void
    private(set) var waiting = false
    private var saving = false
    init(workerRunning: @escaping () -> Bool, pause: @escaping () -> Void, save: @escaping () -> Void,
         reply: @escaping (Bool) -> Void,
         schedule: @escaping (Double,@escaping () -> Void) -> Void = { seconds, task in
             DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:task)
         }) {
        self.workerRunning=workerRunning;self.pause=pause;self.save=save;self.reply=reply;self.schedule=schedule
    }
    func requestSave() -> Bool {
        waiting=false;saving=true;save()
        guard workerRunning() else { return false }
        waiting=true;return true
    }
    func requestPause() -> Bool {
        waiting=false;saving=false;pause()
        guard workerRunning() else { return false }
        waiting=true
        schedule(6) { [weak self] in
            guard let self,self.waiting,!self.saving else{return}
            self.waiting=false;self.reply(true)
        }
        return true
    }
    func changed() {
        guard waiting,!workerRunning() else{return}
        waiting=false;reply(false)
    }
}
