import Vapor

/// Wires up ticket #47's recurring background job: a detached `Task` that
/// calls `NotificationScanService.scan()` every `interval`, for the lifetime
/// of the process — independent of whether the Mac or iOS app is open, the
/// same guarantee `startCalendarSyncSchedule` already gives Calendar sync
/// (spec #1, user story 23; this ticket's own user story 15).
/// `configure(_:)` only calls this outside `app.environment == .testing`
/// (see its own call site): starting it during tests would run real
/// background scans concurrently with test assertions against the same
/// (test) database, racing the very behavior `NotificationScanServiceTests`
/// exercises directly and deterministically instead (user story 16).
func startNotificationScanSchedule(_ app: Application, interval: Duration) {
    let scanService = NotificationScanService(db: app.db, logger: app.logger)
    let task = Task.detached {
        while !Task.isCancelled {
            await scanService.scan()
            try? await Task.sleep(for: interval)
        }
    }
    app.lifecycle.use(NotificationScanScheduleLifecycleHandler(task: task))
}

/// Cancels the scheduled scan loop when the Vapor `Application` shuts down
/// (e.g. a graceful `Ctrl-C`), so the detached `Task` doesn't keep firing
/// against a database connection pool that's already going away — mirrors
/// `CalendarSyncScheduleLifecycleHandler`.
private struct NotificationScanScheduleLifecycleHandler: LifecycleHandler {
    let task: Task<Void, Never>

    func shutdown(_ application: Application) {
        task.cancel()
    }
}
