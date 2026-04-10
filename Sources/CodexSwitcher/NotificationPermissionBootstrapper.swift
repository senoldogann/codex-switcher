import Foundation

struct NotificationPermissionBootstrapper {
    private let schedule: (@escaping @Sendable () -> Void) -> Void

    init(schedule: @escaping (@escaping @Sendable () -> Void) -> Void = { work in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }) {
        self.schedule = schedule
    }

    func scheduleInitialRequest(_ request: @escaping @Sendable () -> Void) {
        schedule(request)
    }
}

struct NotificationPermissionGate {
    private(set) var hasRequested = false

    mutating func runIfNeeded(_ request: () -> Void) {
        guard !hasRequested else { return }
        hasRequested = true
        request()
    }
}
