import Testing
import VaporTesting

@testable import App

/// Covers `GET /v1/school-summary` (issue #92) — the same seam as
/// `FinancesReportingTests`: real HTTP requests against a running Vapor app,
/// backed by a real (test) Postgres database. The arithmetic's own edge
/// cases live in `SchoolFiguresTests`; what's tested here is the scoping —
/// which Courses each figure is computed over.
// Serialized: shares the `courses`/`terms` tables with `CourseTests`.
extension AppTestSuite {
    @Suite("School reporting", .serialized)
    struct SchoolReportingTests {
        @discardableResult
        private func withSchoolApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await Course.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("rejects requests without a bearer token")
        func summaryWithoutTokenIsRejected() async throws {
            try await withSchoolApp { app in
                try await app.testing().test(.GET, "/v1/school-summary", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("cumulative GWA is unit-weighted across Terms, not an average of their averages")
        func cumulativeGWAIsNotAnAverageOfAverages() async throws {
            try await withSchoolApp { app in
                // A heavy 1.00 semester and a light 3.00 one: unit-weighted
                // this is (1.00×6 + 3.00×1) ÷ 7 = 1.285…, while averaging the
                // two semesters' own figures would wrongly give 2.00.
                try await makeCourse(
                    name: "Thermo", on: app.db, year: 2026, semester: .first, units: 6, grade: .one)
                try await makeCourse(
                    name: "PE", on: app.db, year: 2026, semester: .second, units: 1, grade: .three)

                try await app.testing().test(
                    .GET, "/v1/school-summary", headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(SchoolSummaryResponse.self)
                        #expect(abs((body.cumulativeGWA ?? 0) - 9.0 / 7.0) < 0.000_001)
                        #expect(body.unitsEarned == 7)
                        // No termID asked for, so no Term figure is claimed.
                        #expect(body.termID == nil)
                        #expect(body.termGWA == nil)
                    }
                )
            }
        }

        @Test("termID scopes only the Term figure — Units Earned stays cumulative")
        func termScopeAppliesToGWAOnly() async throws {
            try await withSchoolApp { app in
                let current = try await makeTerm(on: app.db, year: 2027, semester: .first)
                let currentID = try current.requireID()
                try await makeCourse(
                    name: "Signals", on: app.db, year: 2027, semester: .first, units: 3, grade: .two)
                try await makeCourse(
                    name: "History", on: app.db, year: 2026, semester: .first, units: 3, grade: .one)

                try await app.testing().test(
                    .GET, "/v1/school-summary?termID=\(currentID)", headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(SchoolSummaryResponse.self)
                        #expect(body.termID == currentID)
                        #expect(abs((body.termGWA ?? 0) - 2.0) < 0.000_001)
                        #expect(abs((body.cumulativeGWA ?? 0) - 1.5) < 0.000_001)
                        #expect(body.unitsEarned == 6)
                    }
                )
            }
        }

        @Test("a failed subject drags GWA down but earns no units")
        func failureEarnsNoUnits() async throws {
            try await withSchoolApp { app in
                try await makeCourse(
                    name: "Calculus", on: app.db, year: 2026, semester: .first, units: 3, grade: .five)
                try await makeCourse(
                    name: "Ethics", on: app.db, year: 2026, semester: .first, units: 3, grade: .one)

                try await app.testing().test(
                    .GET, "/v1/school-summary", headers: authHeaders(),
                    afterResponse: { res async throws in
                        let body = try res.content.decode(SchoolSummaryResponse.self)
                        #expect(abs((body.cumulativeGWA ?? 0) - 3.0) < 0.000_001)
                        #expect(body.unitsEarned == 3)
                    }
                )
            }
        }

        @Test("ongoing subjects leave GWA absent rather than zero")
        func noGradedCoursesYieldsNullGWA() async throws {
            try await withSchoolApp { app in
                try await makeCourse(name: "Thesis", on: app.db, units: 3, grade: nil)
                try await makeCourse(name: "Elective", on: app.db, units: 3, grade: .incomplete)

                try await app.testing().test(
                    .GET, "/v1/school-summary", headers: authHeaders(),
                    afterResponse: { res async throws in
                        let body = try res.content.decode(SchoolSummaryResponse.self)
                        #expect(body.cumulativeGWA == nil)
                        #expect(body.unitsEarned == 0)
                    }
                )
            }
        }

        @Test("rejects a termID naming no Term")
        func rejectsUnknownTerm() async throws {
            try await withSchoolApp { app in
                try await app.testing().test(
                    .GET, "/v1/school-summary?termID=\(UUID())", headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }
    }
}
