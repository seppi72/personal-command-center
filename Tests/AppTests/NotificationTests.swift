import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `AutomationLogTests`/`DeadlineTests`: real HTTP requests
/// against a running Vapor app, backed by a real (test) Postgres database.
/// Nothing in this codebase auto-creates a `PCCNotification` yet (tickets
/// #46/#47's job) — every row here is inserted directly, the same way
/// ticket #36 (Account CRUD) demoed Balance before any Transaction existed
/// to generate one.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation). This suite owns the `notifications` table exclusively
// (nothing else writes to it yet), but stays serialized to match every other
// integration suite's convention, and cleans up after itself regardless.
extension AppTestSuite {
    @Suite("Notification", .serialized)
    struct NotificationTests {
        @discardableResult
        private func withNotificationApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await PCCNotification.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @discardableResult
        private func makeNotification(
            on db: any Database,
            sourceType: String = "PCCTask",
            sourceID: UUID = UUID(),
            message: String = "Task is overdue",
            isDismissed: Bool = false
        ) async throws -> PCCNotification {
            let notification = PCCNotification(
                sourceType: sourceType,
                sourceID: sourceID,
                message: message,
                isDismissed: isDismissed
            )
            try await notification.save(on: db)
            return notification
        }

        @Test("rejects requests without a bearer token")
        func notificationsWithoutTokenAreRejected() async throws {
            try await withNotificationApp { app in
                try await app.testing().test(.GET, "/v1/notifications", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("lists only undismissed Notifications, newest first")
        func listsOnlyUndismissedNotificationsNewestFirst() async throws {
            try await withNotificationApp { app in
                let older = try await makeNotification(on: app.db, message: "First overdue Task")
                try await Task.sleep(for: .milliseconds(10))
                let newer = try await makeNotification(on: app.db, message: "Second overdue Task")
                try await makeNotification(on: app.db, message: "Already handled", isDismissed: true)

                try await app.testing().test(
                    .GET, "/v1/notifications",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([NotificationResponse].self)
                        #expect(body.count == 2)
                        #expect(body.first?.id == newer.id)
                        #expect(body.last?.id == older.id)
                        #expect(body.allSatisfy { !$0.isDismissed })
                    }
                )
            }
        }

        @Test("returns an empty list when nothing is open")
        func emptyWhenNothingOpen() async throws {
            try await withNotificationApp { app in
                try await app.testing().test(
                    .GET, "/v1/notifications",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([NotificationResponse].self)
                        #expect(body.isEmpty)
                    }
                )
            }
        }

        @Test("dismiss sets isDismissed and removes it from the open list")
        func dismissSetsFlagAndRemovesFromOpenList() async throws {
            try await withNotificationApp { app in
                let notification = try await makeNotification(on: app.db)

                try await app.testing().test(
                    .POST, "/v1/notifications/\(notification.id!)/dismiss",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(NotificationResponse.self)
                        #expect(body.id == notification.id)
                        #expect(body.isDismissed == true)
                    }
                )

                try await app.testing().test(
                    .GET, "/v1/notifications",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let body = try res.content.decode([NotificationResponse].self)
                        #expect(body.isEmpty)
                    }
                )
            }
        }

        @Test("dismiss is idempotent on a second call")
        func dismissIsIdempotent() async throws {
            try await withNotificationApp { app in
                let notification = try await makeNotification(on: app.db)

                try await app.testing().test(
                    .POST, "/v1/notifications/\(notification.id!)/dismiss",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .ok)
                    }
                )
                try await app.testing().test(
                    .POST, "/v1/notifications/\(notification.id!)/dismiss",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(NotificationResponse.self)
                        #expect(body.isDismissed == true)
                    }
                )
            }
        }

        @Test("dismissing an unknown Notification 404s")
        func dismissUnknownNotificationReturnsNotFound() async throws {
            try await withNotificationApp { app in
                try await app.testing().test(
                    .POST, "/v1/notifications/\(UUID())/dismiss",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("has no DELETE route — dismissed rows are kept for history")
        func hasNoDeleteRoute() async throws {
            try await withNotificationApp { app in
                let notification = try await makeNotification(on: app.db)
                try await app.testing().test(
                    .DELETE, "/v1/notifications/\(notification.id!)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }
    }
}
