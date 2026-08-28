import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

/// Exercises `NotificationScanService.scan()` directly against a real (test)
/// Postgres database — no HTTP request to drive here, the same way
/// `CalendarSyncServiceTests` calls `CalendarSyncService`'s methods directly
/// rather than going through `CalendarSyncSchedule`'s loop (ticket #47's own
/// AC).
// Serialized: shares `tasks`/`projects`/`courses` with `DeadlineTests`/
// `ProjectTests`/`TaskTests`, and shares `notifications` with
// `NotificationTests` — none of them run concurrently under
// `AppTestSuite`'s own `.serialized` trait, but this suite still cleans up
// after itself regardless, matching every other integration suite's
// convention.
extension AppTestSuite {
    @Suite("NotificationScanService", .serialized)
    struct NotificationScanServiceTests {
        @discardableResult
        private func withScanApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await PCCNotification.query(on: app.db).delete()
                try await PCCTask.query(on: app.db).delete()
                try await Project.query(on: app.db).delete()
                try await Course.query(on: app.db).delete()
                return result
            }
        }

        private func scanService(_ app: Application) -> NotificationScanService {
            NotificationScanService(db: app.db, logger: app.logger)
        }

        private func openNotifications(on app: Application) async throws -> [PCCNotification] {
            try await PCCNotification.query(on: app.db)
                .filter(\.$isDismissed == false)
                .all()
        }

        private let past = Date(timeIntervalSince1970: 1_600_000_000)
        private let future = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)

        // MARK: - Creation

        @Test("creates a Notification for a newly-overdue, incomplete Task")
        func createsNotificationForOverdueTask() async throws {
            try await withScanApp { app in
                let task = PCCTask(title: "Renew passport", dueDate: past)
                try await task.save(on: app.db)

                await scanService(app).scan()

                let open = try await openNotifications(on: app)
                #expect(open.count == 1)
                #expect(open.first?.sourceType == "PCCTask")
                #expect(open.first?.sourceID == task.id)
                #expect(open.first?.message == "Task 'Renew passport' is overdue")
            }
        }

        @Test("creates a Notification for a newly-overdue Project")
        func createsNotificationForOverdueProject() async throws {
            try await withScanApp { app in
                let project = Project(name: "Launch", dueDate: past)
                try await project.save(on: app.db)

                await scanService(app).scan()

                let open = try await openNotifications(on: app)
                #expect(open.count == 1)
                #expect(open.first?.sourceType == "Project")
                #expect(open.first?.sourceID == project.id)
                #expect(open.first?.message == "Project 'Launch' is overdue")
            }
        }

        @Test("creates a Notification for a newly-overdue Course")
        func createsNotificationForOverdueCourse() async throws {
            try await withScanApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026, dueDate: past)
                try await course.save(on: app.db)

                await scanService(app).scan()

                let open = try await openNotifications(on: app)
                #expect(open.count == 1)
                #expect(open.first?.sourceType == "Course")
                #expect(open.first?.sourceID == course.id)
                #expect(open.first?.message == "Course 'CS 301' is overdue")
            }
        }

        @Test("does not create a Notification for a complete overdue Task")
        func skipsCompleteOverdueTask() async throws {
            try await withScanApp { app in
                let task = PCCTask(title: "Already done", isComplete: true, dueDate: past)
                try await task.save(on: app.db)

                await scanService(app).scan()

                #expect(try await openNotifications(on: app).isEmpty)
            }
        }

        @Test("does not create a Notification for an undated or not-yet-due item")
        func skipsUndatedAndFutureItems() async throws {
            try await withScanApp { app in
                try await PCCTask(title: "No due date").save(on: app.db)
                try await PCCTask(title: "Due later", dueDate: future).save(on: app.db)
                try await Project(name: "Due later").save(on: app.db)

                await scanService(app).scan()

                #expect(try await openNotifications(on: app).isEmpty)
            }
        }

        @Test("a second scan of the same still-overdue Task doesn't duplicate its Notification")
        func doesNotDuplicateOnRepeatedScan() async throws {
            try await withScanApp { app in
                let task = PCCTask(title: "Renew passport", dueDate: past)
                try await task.save(on: app.db)

                await scanService(app).scan()
                await scanService(app).scan()

                let open = try await openNotifications(on: app)
                #expect(open.count == 1)
            }
        }

        // MARK: - Auto-clear

        @Test("auto-clears a Notification once its Task is completed")
        func autoClearsOnCompletion() async throws {
            try await withScanApp { app in
                let task = PCCTask(title: "Renew passport", dueDate: past)
                try await task.save(on: app.db)
                await scanService(app).scan()
                #expect(try await openNotifications(on: app).count == 1)

                task.isComplete = true
                try await task.save(on: app.db)
                await scanService(app).scan()

                #expect(try await openNotifications(on: app).isEmpty)
                let all = try await PCCNotification.query(on: app.db).all()
                #expect(all.count == 1)
                #expect(all.first?.isDismissed == true)
            }
        }

        @Test("auto-clears a Notification once its Project's due date moves to the future")
        func autoClearsOnDueDateMovedForward() async throws {
            try await withScanApp { app in
                let project = Project(name: "Launch", dueDate: past)
                try await project.save(on: app.db)
                await scanService(app).scan()
                #expect(try await openNotifications(on: app).count == 1)

                project.dueDate = future
                try await project.save(on: app.db)
                await scanService(app).scan()

                #expect(try await openNotifications(on: app).isEmpty)
            }
        }

        @Test("auto-clears a Notification once its source Course is deleted")
        func autoClearsOnDeletion() async throws {
            try await withScanApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026, dueDate: past)
                try await course.save(on: app.db)
                await scanService(app).scan()
                #expect(try await openNotifications(on: app).count == 1)

                try await course.delete(force: true, on: app.db)
                await scanService(app).scan()

                #expect(try await openNotifications(on: app).isEmpty)
            }
        }

        @Test("a Notification dismissed while its Task is still overdue stays dismissed — the scan never re-opens that row")
        func dismissedRowIsNeverReopened() async throws {
            try await withScanApp { app in
                let task = PCCTask(title: "Renew passport", dueDate: past)
                try await task.save(on: app.db)
                await scanService(app).scan()
                let first = try #require(try await PCCNotification.query(on: app.db).first())
                first.isDismissed = true
                try await first.save(on: app.db)

                // The item is still overdue, and dedup only ever checks
                // *open* Notifications (ticket #47's AC) — so a fresh row
                // opens for it. What User Story 10 promises is that the
                // dismissed row itself never flips back to open, which the
                // second assertion below confirms.
                await scanService(app).scan()

                let open = try await openNotifications(on: app)
                #expect(open.count == 1)
                #expect(open.first?.id != first.id)

                let firstReloaded = try await PCCNotification.find(first.requireID(), on: app.db)
                #expect(firstReloaded?.isDismissed == true)
            }
        }
    }
}
