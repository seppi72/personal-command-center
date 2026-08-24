import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `ProjectTests`/`TaskTests`/`MirroredCalendarEventTests`: real
/// HTTP requests against a running Vapor app, backed by a real (test)
/// Postgres database. Read-only, per `AutomationLogController` — only
/// `index` exists to test.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation). Owns no table exclusively — `automation_logs` is
// also written to by `PersonalCommitmentTests`/`CalendarSyncServiceTests`,
// so this suite cleans up after itself the same way those do.
extension AppTestSuite {
    @Suite("Automation Log", .serialized)
    struct AutomationLogTests {
        @discardableResult
        private func withAutomationLogApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await AutomationLog.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @discardableResult
        private func makeLog(
            on db: any Database,
            actionType: String = "personal_commitment.create",
            subjectType: String = "PersonalCommitment",
            detail: String = "Pushed to CalDAV",
            outcome: AutomationLog.Outcome = .success
        ) async throws -> AutomationLog {
            let entry = AutomationLog(
                actionType: actionType,
                subjectType: subjectType,
                subjectID: UUID(),
                detail: detail,
                outcome: outcome
            )
            try await entry.save(on: db)
            return entry
        }

        @Test("rejects requests without a bearer token")
        func automationLogsWithoutTokenAreRejected() async throws {
            try await withAutomationLogApp { app in
                try await app.testing().test(.GET, "/v1/automation-logs", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("lists Automation Log entries, most recent first")
        func listsEntriesMostRecentFirst() async throws {
            try await withAutomationLogApp { app in
                let older = try await makeLog(on: app.db, actionType: "calendar.pull", detail: "Pulled new event from CalDAV")
                try await Task.sleep(for: .milliseconds(10))
                let newer = try await makeLog(on: app.db, actionType: "personal_commitment.create", detail: "Pushed to CalDAV")

                try await app.testing().test(
                    .GET, "/v1/automation-logs",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(AutomationLogsResponse.self)
                        #expect(body.entries.count == 2)
                        #expect(body.entries.first?.id == newer.id)
                        #expect(body.entries.last?.id == older.id)
                        #expect(body.entries.first?.actionType == "personal_commitment.create")
                        #expect(body.entries.first?.outcome == "success")
                    }
                )
            }
        }

        @Test("surfaces the most recent sync failure separately from the entry list")
        func surfacesMostRecentFailure() async throws {
            try await withAutomationLogApp { app in
                try await makeLog(on: app.db, actionType: "calendar.pull", outcome: .success)
                let firstFailure = try await makeLog(
                    on: app.db,
                    actionType: "personal_commitment.create",
                    detail: "CalDAV push failed: timed out",
                    outcome: .failure
                )
                try await Task.sleep(for: .milliseconds(10))
                let latestFailure = try await makeLog(
                    on: app.db,
                    actionType: "calendar.pull",
                    detail: "CalDAV pull failed: server error",
                    outcome: .failure
                )
                try await Task.sleep(for: .milliseconds(10))
                try await makeLog(on: app.db, actionType: "personal_commitment.create", outcome: .success)

                try await app.testing().test(
                    .GET, "/v1/automation-logs",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(AutomationLogsResponse.self)
                        #expect(body.mostRecentFailure?.id == latestFailure.id)
                        #expect(body.mostRecentFailure?.id != firstFailure.id)
                        #expect(body.mostRecentFailure?.detail == "CalDAV pull failed: server error")
                    }
                )
            }
        }

        @Test("mostRecentFailure is nil when nothing has ever failed")
        func mostRecentFailureIsNilWhenNothingFailed() async throws {
            try await withAutomationLogApp { app in
                try await makeLog(on: app.db, outcome: .success)

                try await app.testing().test(
                    .GET, "/v1/automation-logs",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(AutomationLogsResponse.self)
                        #expect(body.mostRecentFailure == nil)
                    }
                )
            }
        }

        @Test("returns an empty list and no failure when nothing has happened yet")
        func emptyWhenNoEntries() async throws {
            try await withAutomationLogApp { app in
                try await app.testing().test(
                    .GET, "/v1/automation-logs",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(AutomationLogsResponse.self)
                        #expect(body.entries.isEmpty)
                        #expect(body.mostRecentFailure == nil)
                    }
                )
            }
        }

        @Test("has no create, update, or delete routes — the log is read-only")
        func hasNoWriteRoutes() async throws {
            try await withAutomationLogApp { app in
                try await app.testing().test(
                    .POST, "/v1/automation-logs",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
                try await app.testing().test(
                    .DELETE, "/v1/automation-logs/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }
    }
}
