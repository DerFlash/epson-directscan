final class ConnectionActions {
    let hasConsent: () -> Bool
    let requestConsent: () -> Bool
    let rememberConsent: () -> Void
    let connectAction: () -> Void
    let recoverAction: () -> Void
    init(hasConsent: @escaping () -> Bool, requestConsent: @escaping () -> Bool,
         rememberConsent: @escaping () -> Void, connect: @escaping () -> Void, recover: @escaping () -> Void) {
        self.hasConsent = hasConsent; self.requestConsent = requestConsent; self.rememberConsent = rememberConsent
        self.connectAction = connect; self.recoverAction = recover
    }
    private func authorized(_ action: () -> Void) {
        if !hasConsent() {
            guard requestConsent() else { return }
            rememberConsent()
        }
        action()
    }
    func connect() { authorized(connectAction) }
    func recover() { authorized(recoverAction) }
}
