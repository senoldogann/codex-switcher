import Testing
@testable import CodexSwitcher

struct NotificationPermissionBootstrapperTests {

    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    @Test("scheduleInitialRequest defers execution until scheduled work runs")
    func bootstrapperDefersExecution() {
        var scheduledWork: (() -> Void)?
        let bootstrapper = NotificationPermissionBootstrapper { work in
            scheduledWork = work
        }

        let counter = Counter()
        bootstrapper.scheduleInitialRequest {
            counter.value += 1
        }

        #expect(counter.value == 0)
        #expect(scheduledWork != nil)

        scheduledWork?()

        #expect(counter.value == 1)
    }

    @Test("notification gate runs request only once")
    func notificationGateRunsOnlyOnce() {
        var gate = NotificationPermissionGate()
        var requestCount = 0

        gate.runIfNeeded {
            requestCount += 1
        }
        gate.runIfNeeded {
            requestCount += 1
        }

        #expect(requestCount == 1)
    }
}
