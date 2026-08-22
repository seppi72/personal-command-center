import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `ProjectTests`/`TaskTests`/`PersonalCommitmentTests`: real
/// HTTP requests against a running Vapor app, backed by a real (test)
/// Postgres database. Read-only, per `MirroredCalendarEventController` —
/// only `index` exists to test.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation). Owns `mirrored_calendar_events`, which
// `CalendarSyncServiceTests` also touches.
extension AppTestSuite {
    @Suite("Mirrored Calendar Events", .serialized)
    struct MirroredCalendarEventTests {
        @discardableResult
        private func withCalendarEventsApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await MirroredCalendarEvent.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("rejects requests without a bearer token")
        func calendarEventsWithoutTokenAreRejected() async throws {
            try await withCalendarEventsApp { app in
                try await app.testing().test(.GET, "/v1/calendar-events", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("lists mirrored Calendar events pulled from CalDAV")
        func listsMirroredEvents() async throws {
            try await withCalendarEventsApp { app in
                try await MirroredCalendarEvent(
                    externalEventID: "ext-1",
                    title: "Dentist (mirrored)",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600)
                ).save(on: app.db)
                try await MirroredCalendarEvent(
                    externalEventID: "ext-2",
                    title: "Flight",
                    startDate: Date(timeIntervalSince1970: 1_900_000_000),
                    endDate: Date(timeIntervalSince1970: 1_900_003_600)
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/calendar-events",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([MirroredCalendarEventResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.title)) == ["Dentist (mirrored)", "Flight"])
                    }
                )
            }
        }

        @Test("has no create, update, or delete routes — the cache is read-only")
        func hasNoWriteRoutes() async throws {
            try await withCalendarEventsApp { app in
                try await app.testing().test(
                    .POST, "/v1/calendar-events",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
                try await app.testing().test(
                    .DELETE, "/v1/calendar-events/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }
    }
}
