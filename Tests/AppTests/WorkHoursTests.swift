import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `TimeEntryTests`: real HTTP requests against a running
/// Vapor app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Work Hours", .serialized)
    struct WorkHoursTests {
        /// The endpoint's response shape differs by `groupBy` (`WorkHoursRow`)
        /// — one small `Content` type per shape, decoded into whichever one a
        /// given test's own `groupBy` produces.
        private struct DayRow: Content { let date: Date; let totalSeconds: Double }
        private struct ProjectRow: Content { let projectID: UUID; let projectName: String; let totalSeconds: Double }
        private struct ClientRow: Content { let clientID: UUID; let clientName: String; let totalSeconds: Double }
        private struct TaskRow: Content { let taskID: UUID; let taskName: String; let totalSeconds: Double }
        private struct CourseRow: Content { let courseID: UUID; let courseName: String; let totalSeconds: Double }

        @discardableResult
        private func withWorkHoursApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await TimeEntry.query(on: app.db).delete()
                try await PCCTask.query(on: app.db).delete()
                try await Project.query(on: app.db).delete()
                try await PCCClient.query(on: app.db).delete()
                try await Course.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        private func makeTask(_ app: Application, title: String = "Task", projectID: UUID? = nil, courseID: UUID? = nil) async throws -> PCCTask {
            let task = PCCTask(title: title, projectID: projectID, courseID: courseID)
            try await task.save(on: app.db)
            return task
        }

        private func makeProject(
            _ app: Application, name: String = "Project", clientID: UUID? = nil, courseID: UUID? = nil
        ) async throws -> Project {
            let project = Project(name: name, clientID: clientID, courseID: courseID)
            try await project.save(on: app.db)
            return project
        }

        private func makeClient(_ app: Application, name: String = "Client") async throws -> PCCClient {
            let client = PCCClient(name: name)
            try await client.save(on: app.db)
            return client
        }

        private func makeCourse(_ app: Application, name: String = "Course") async throws -> Course {
            let course = Course(name: name, termMonth: 9, termYear: 2026)
            try await course.save(on: app.db)
            return course
        }

        @discardableResult
        private func makeEntry(
            _ app: Application, start: Date, end: Date?, container: TimeEntryContainer
        ) async throws -> TimeEntry {
            // Bypasses `TimeEntryController.verifyNoOverlap` — inserted
            // directly via the model, same as `TimeEntryTests`'s own fixture
            // helpers, since Work Hours totals don't care whether the spans
            // that produced them could have all come from real API calls.
            let entry = TimeEntry(startDate: start, endDate: end, container: container)
            try await entry.save(on: app.db)
            return entry
        }

        private static func isoString(_ date: Date) -> String {
            ISO8601DateFormatter().string(from: date)
        }

        private func path(groupBy: String, start: Date, end: Date) -> String {
            "/v1/work-hours?groupBy=\(groupBy)&start=\(Self.isoString(start))&end=\(Self.isoString(end))"
        }

        @Test("rejects requests without a bearer token")
        func rejectsWithoutToken() async throws {
            try await withWorkHoursApp { app in
                let now = Date()
                try await app.testing().test(
                    .GET, path(groupBy: "day", start: now, end: now.addingTimeInterval(86400)),
                    afterResponse: { res async in
                        #expect(res.status == .unauthorized)
                    }
                )
            }
        }

        @Test("rejects a missing or invalid groupBy")
        func rejectsInvalidGroupBy() async throws {
            try await withWorkHoursApp { app in
                let now = Date()
                let start = Self.isoString(now)
                let end = Self.isoString(now.addingTimeInterval(86400))

                try await app.testing().test(
                    .GET, "/v1/work-hours?start=\(start)&end=\(end)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
                try await app.testing().test(
                    .GET, "/v1/work-hours?groupBy=sprint&start=\(start)&end=\(end)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("rejects a missing start or end")
        func rejectsMissingRange() async throws {
            try await withWorkHoursApp { app in
                try await app.testing().test(
                    .GET, "/v1/work-hours?groupBy=day&end=\(Self.isoString(Date()))",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
                try await app.testing().test(
                    .GET, "/v1/work-hours?groupBy=day&start=\(Self.isoString(Date()))",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("rejects an inverted range")
        func rejectsInvertedRange() async throws {
            try await withWorkHoursApp { app in
                let now = Date()
                try await app.testing().test(
                    .GET, path(groupBy: "day", start: now, end: now.addingTimeInterval(-86400)),
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
                try await app.testing().test(
                    .GET, path(groupBy: "day", start: now, end: now),
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("groupBy=day is dense: every calendar day in range appears, including one with nothing logged")
        func dayRowsAreDense() async throws {
            try await withWorkHoursApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let task = try await makeTask(app)
                // One hour logged on "today"; "tomorrow" gets nothing.
                try await makeEntry(
                    app,
                    start: today.addingTimeInterval(3600),
                    end: today.addingTimeInterval(7200),
                    container: .task(try task.requireID())
                )
                let rangeStart = today
                let rangeEnd = calendar.date(byAdding: .day, value: 2, to: today)!

                try await app.testing().test(
                    .GET, path(groupBy: "day", start: rangeStart, end: rangeEnd),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let rows = try res.content.decode([DayRow].self)
                        #expect(rows.count == 2)
                        #expect(abs(rows[0].date.timeIntervalSince(today)) < 1)
                        #expect(rows[0].totalSeconds == 3600)
                        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                        #expect(abs(rows[1].date.timeIntervalSince(tomorrow)) < 1)
                        #expect(rows[1].totalSeconds == 0)
                    }
                )
            }
        }

        @Test("an entry spanning midnight counts entirely toward its start day")
        func entrySpanningMidnightCountsTowardStartDay() async throws {
            try await withWorkHoursApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let task = try await makeTask(app)
                // Starts one hour before midnight, ends one hour after.
                try await makeEntry(
                    app,
                    start: today.addingTimeInterval(-3600),
                    end: today.addingTimeInterval(3600),
                    container: .task(try task.requireID())
                )
                let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
                let rangeEnd = calendar.date(byAdding: .day, value: 1, to: today)!

                try await app.testing().test(
                    .GET, path(groupBy: "day", start: yesterday, end: rangeEnd),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([DayRow].self)
                        #expect(rows.count == 2)
                        #expect(rows[0].totalSeconds == 7200)
                        #expect(rows[1].totalSeconds == 0)
                    }
                )
            }
        }

        @Test("groupBy=task is sparse and direct-only")
        func taskRowsAreSparseAndDirect() async throws {
            try await withWorkHoursApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = start.addingTimeInterval(2 * 86400)
                let loggedTask = try await makeTask(app, title: "Logged")
                let quietTask = try await makeTask(app, title: "Quiet")
                _ = quietTask
                try await makeEntry(
                    app, start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200),
                    container: .task(try loggedTask.requireID())
                )

                try await app.testing().test(
                    .GET, path(groupBy: "task", start: start, end: end),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let rows = try res.content.decode([TaskRow].self)
                        #expect(rows.count == 1)
                        #expect(rows[0].taskID == loggedTask.id)
                        #expect(rows[0].taskName == "Logged")
                        #expect(rows[0].totalSeconds == 3600)
                    }
                )
            }
        }

        @Test("groupBy=project folds in entries logged against its Tasks (ADR-0005)")
        func projectRowsFoldTaskEntries() async throws {
            try await withWorkHoursApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = start.addingTimeInterval(86400)
                let project = try await makeProject(app, name: "Website Revamp")
                let projectID = try project.requireID()
                let task = try await makeTask(app, title: "Task", projectID: projectID)

                // Direct-to-Project entry.
                try await makeEntry(
                    app, start: start.addingTimeInterval(0), end: start.addingTimeInterval(1800),
                    container: .project(projectID)
                )
                // Entry on a Task belonging to the Project.
                try await makeEntry(
                    app, start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200),
                    container: .task(try task.requireID())
                )

                try await app.testing().test(
                    .GET, path(groupBy: "project", start: start, end: end),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([ProjectRow].self)
                        #expect(rows.count == 1)
                        #expect(rows[0].projectID == projectID)
                        #expect(rows[0].totalSeconds == 1800 + 3600)
                    }
                )
            }
        }

        @Test("groupBy=course folds in entries logged against its Tasks (ADR-0005)")
        func courseRowsFoldTaskEntries() async throws {
            try await withWorkHoursApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = start.addingTimeInterval(86400)
                let course = try await makeCourse(app, name: "CS 301")
                let courseID = try course.requireID()
                let task = try await makeTask(app, title: "Homework", courseID: courseID)

                try await makeEntry(
                    app, start: start, end: start.addingTimeInterval(900),
                    container: .course(courseID)
                )
                try await makeEntry(
                    app, start: start.addingTimeInterval(3600), end: start.addingTimeInterval(5400),
                    container: .task(try task.requireID())
                )

                try await app.testing().test(
                    .GET, path(groupBy: "course", start: start, end: end),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([CourseRow].self)
                        #expect(rows.count == 1)
                        #expect(rows[0].courseID == courseID)
                        #expect(rows[0].totalSeconds == 900 + 1800)
                    }
                )
            }
        }

        @Test("groupBy=client folds in direct entries and every one of its Projects' already-folded totals")
        func clientRowsFoldProjectTotals() async throws {
            try await withWorkHoursApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = start.addingTimeInterval(86400)
                let client = try await makeClient(app, name: "Acme Co")
                let clientID = try client.requireID()
                let projectWithTaskEntries = try await makeProject(app, name: "Retainer Work", clientID: clientID)
                let projectWithTaskEntriesID = try projectWithTaskEntries.requireID()
                let task = try await makeTask(app, title: "Task", projectID: projectWithTaskEntriesID)
                // A second Project under the same Client with no entries of
                // its own at all — it should fold in as 0, not keep the
                // Client row from appearing (there's still a direct entry).
                _ = try await makeProject(app, name: "Quiet Project", clientID: clientID)

                // Direct-to-Client entry.
                try await makeEntry(
                    app, start: start, end: start.addingTimeInterval(600),
                    container: .client(clientID)
                )
                // Direct-to-Project entry.
                try await makeEntry(
                    app, start: start.addingTimeInterval(1800), end: start.addingTimeInterval(3600),
                    container: .project(projectWithTaskEntriesID)
                )
                // Entry on a Task under that Project.
                try await makeEntry(
                    app, start: start.addingTimeInterval(7200), end: start.addingTimeInterval(9000),
                    container: .task(try task.requireID())
                )

                try await app.testing().test(
                    .GET, path(groupBy: "client", start: start, end: end),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([ClientRow].self)
                        #expect(rows.count == 1)
                        #expect(rows[0].clientID == clientID)
                        #expect(rows[0].totalSeconds == 600 + 1800 + 1800)
                    }
                )
            }
        }

        @Test("a running timer contributes nothing to any total until stopped")
        func runningTimerContributesNothing() async throws {
            try await withWorkHoursApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = start.addingTimeInterval(86400)
                let task = try await makeTask(app, title: "In progress")
                try await makeEntry(app, start: start.addingTimeInterval(3600), end: nil, container: .task(try task.requireID()))

                try await app.testing().test(
                    .GET, path(groupBy: "task", start: start, end: end),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([TaskRow].self)
                        #expect(rows.isEmpty)
                    }
                )
            }
        }

        @Test("an entry starting outside the range is excluded")
        func entryOutsideRangeIsExcluded() async throws {
            try await withWorkHoursApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = start.addingTimeInterval(86400)
                let task = try await makeTask(app, title: "Out of range")
                try await makeEntry(
                    app, start: end.addingTimeInterval(3600), end: end.addingTimeInterval(7200),
                    container: .task(try task.requireID())
                )

                try await app.testing().test(
                    .GET, path(groupBy: "task", start: start, end: end),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([TaskRow].self)
                        #expect(rows.isEmpty)
                    }
                )
            }
        }

        @Test("groupBy=course folds in its Projects' totals (ADR-0011)")
        func courseRowsFoldOwnedProjectTotals() async throws {
            try await withWorkHoursApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = start.addingTimeInterval(86400)
                let course = try await makeCourse(app, name: "CS 301")
                let courseID = try course.requireID()
                let project = try await makeProject(app, name: "Group assignment", courseID: courseID)
                let projectID = try project.requireID()
                let task = try await makeTask(app, title: "Slides", projectID: projectID)

                // One entry per level of the fold: direct-to-Course, direct
                // to the Course's Project, and against a Task inside it.
                try await makeEntry(
                    app, start: start, end: start.addingTimeInterval(900),
                    container: .course(courseID)
                )
                try await makeEntry(
                    app, start: start.addingTimeInterval(3600), end: start.addingTimeInterval(5400),
                    container: .project(projectID)
                )
                try await makeEntry(
                    app, start: start.addingTimeInterval(7200), end: start.addingTimeInterval(7200 + 600),
                    container: .task(try task.requireID())
                )

                try await app.testing().test(
                    .GET, path(groupBy: "course", start: start, end: end),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([CourseRow].self)
                        #expect(rows.count == 1)
                        #expect(rows[0].courseID == courseID)
                        #expect(rows[0].totalSeconds == 900 + 1800 + 600)
                    }
                )
            }
        }

        @Test("a Course-owned Project's hours don't leak into any Client total")
        func courseOwnedProjectDoesNotCountTowardAClient() async throws {
            try await withWorkHoursApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = start.addingTimeInterval(86400)
                let client = try await makeClient(app, name: "Acme")
                let course = try await makeCourse(app, name: "CS 301")
                let project = try await makeProject(
                    app, name: "Group assignment", courseID: try course.requireID()
                )

                try await makeEntry(
                    app, start: start, end: start.addingTimeInterval(900),
                    container: .project(try project.requireID())
                )

                try await app.testing().test(
                    .GET, path(groupBy: "client", start: start, end: end),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([ClientRow].self)
                        #expect(!rows.contains { $0.clientID == (try? client.requireID()) })
                    }
                )
            }
        }
    }
}
