import Vapor

/// Wires up ticket #7's recurring background job: a detached `Task` that
/// calls `CalendarSyncService.runScheduledSync()` every `interval`, for the
/// lifetime of the process — independent of whether the Mac or iOS app is
/// open (spec #1, user story 23). `configure(_:)` only calls this outside
/// `app.environment == .testing` (see its own call site): starting it
/// during tests would run real background pull/push cycles concurrently
/// with test assertions against the same (test) database, racing the very
/// behavior `CalendarSyncServiceTests` exercises directly and
/// deterministically instead.
func startCalendarSyncSchedule(_ app: Application, interval: Duration) {
    let syncService = CalendarSyncService(calDAVClient: app.calDAVClient, db: app.db, logger: app.logger)
    let task = Task.detached {
        while !Task.isCancelled {
            await syncService.runScheduledSync()
            try? await Task.sleep(for: interval)
        }
    }
    app.lifecycle.use(CalendarSyncScheduleLifecycleHandler(task: task))
}

/// Cancels the scheduled sync loop when the Vapor `Application` shuts down
/// (e.g. a graceful `Ctrl-C`), so the detached `Task` doesn't keep firing
/// against a database connection pool that's already going away.
private struct CalendarSyncScheduleLifecycleHandler: LifecycleHandler {
    let task: Task<Void, Never>

    func shutdown(_ application: Application) {
        task.cancel()
    }
}
