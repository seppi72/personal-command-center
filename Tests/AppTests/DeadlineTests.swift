import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `ProjectTests`/`TaskTests`: real HTTP requests against a
/// running Vapor app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows —
// including with `ProjectTests`/`TaskTests`, which share these same tables.
extension AppTestSuite {
    @Suite("Deadlines", .serialized)
    struct DeadlineTests {
        @discardableResult
        private func withDeadlinesApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await PCCTask.query(on: app.db).delete()
                try await Project.query(on: app.db).delete()
                try await Course.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        // MARK: - Attach/change/remove on a Task

        @Test("attaches a Deadline to a Task")
        func attachesTaskDeadline() async throws {
            try await withDeadlinesApp { app in
                let task = PCCTask(title: "Ship it")
                try await task.save(on: app.db)
                let id = try task.requireID()
                let dueDate = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetTaskDeadlineRequest(dueDate: dueDate))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.dueDate == dueDate)
                    }
                )

                let stored = try await PCCTask.find(id, on: app.db)
                #expect(stored?.dueDate == dueDate)
            }
        }

        @Test("attaches a Deadline to a Course-scoped Task, the same way as a Project-scoped Task")
        func attachesDeadlineToCourseScopedTask() async throws {
            try await withDeadlinesApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let task = PCCTask(title: "Problem set", courseID: try course.requireID())
                try await task.save(on: app.db)
                let id = try task.requireID()
                let dueDate = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetTaskDeadlineRequest(dueDate: dueDate))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.dueDate == dueDate)
                        #expect(body.courseID == course.id)
                    }
                )

                let stored = try await PCCTask.find(id, on: app.db)
                #expect(stored?.dueDate == dueDate)
                #expect(stored?.$course.id == course.id)
            }
        }

        @Test("changes a Task's Deadline, then removes it")
        func changesAndRemovesTaskDeadline() async throws {
            try await withDeadlinesApp { app in
                let firstDueDate = Date(timeIntervalSince1970: 1_800_000_000)
                let task = PCCTask(title: "Reschedule me", dueDate: firstDueDate)
                try await task.save(on: app.db)
                let id = try task.requireID()
                let secondDueDate = Date(timeIntervalSince1970: 1_900_000_000)

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetTaskDeadlineRequest(dueDate: secondDueDate))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.dueDate == secondDueDate)
                    }
                )
                #expect(try await PCCTask.find(id, on: app.db)?.dueDate == secondDueDate)

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetTaskDeadlineRequest(dueDate: nil))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.dueDate == nil)
                    }
                )
                #expect(try await PCCTask.find(id, on: app.db)?.dueDate == nil)
            }
        }

        @Test("setting a Deadline on a Task that doesn't exist 404s")
        func settingMissingTaskDeadlineFails() async throws {
            try await withDeadlinesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/tasks/\(UUID())/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetTaskDeadlineRequest(dueDate: Date()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        // MARK: - Attach/change/remove on a Project

        @Test("attaches a Deadline to a Project")
        func attachesProjectDeadline() async throws {
            try await withDeadlinesApp { app in
                let project = Project(name: "Launch")
                try await project.save(on: app.db)
                let id = try project.requireID()
                let dueDate = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectDeadlineRequest(dueDate: dueDate))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.dueDate == dueDate)
                    }
                )

                let stored = try await Project.find(id, on: app.db)
                #expect(stored?.dueDate == dueDate)
            }
        }

        @Test("changes a Project's Deadline, then removes it")
        func changesAndRemovesProjectDeadline() async throws {
            try await withDeadlinesApp { app in
                let firstDueDate = Date(timeIntervalSince1970: 1_800_000_000)
                let project = Project(name: "Reschedule me", dueDate: firstDueDate)
                try await project.save(on: app.db)
                let id = try project.requireID()
                let secondDueDate = Date(timeIntervalSince1970: 1_900_000_000)

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectDeadlineRequest(dueDate: secondDueDate))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.dueDate == secondDueDate)
                    }
                )
                #expect(try await Project.find(id, on: app.db)?.dueDate == secondDueDate)

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectDeadlineRequest(dueDate: nil))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.dueDate == nil)
                    }
                )
                #expect(try await Project.find(id, on: app.db)?.dueDate == nil)
            }
        }

        @Test("setting a Deadline on a Project that doesn't exist 404s")
        func settingMissingProjectDeadlineFails() async throws {
            try await withDeadlinesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/projects/\(UUID())/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectDeadlineRequest(dueDate: Date()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        // MARK: - The sorted view

        @Test("rejects requests without a bearer token")
        func deadlinesWithoutTokenAreRejected() async throws {
            try await withDeadlinesApp { app in
                try await app.testing().test(.GET, "/v1/deadlines", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("lists Tasks and Projects ordered by Deadline proximity, undated items still included")
        func listsDeadlinesByProximity() async throws {
            try await withDeadlinesApp { app in
                let soon = Date(timeIntervalSince1970: 1_700_000_000)
                let sooner = Date(timeIntervalSince1970: 1_600_000_000)
                let soonest = Date(timeIntervalSince1970: 1_500_000_000)

                try await PCCTask(title: "Task due last", dueDate: soon).save(on: app.db)
                try await Project(name: "Project due first", dueDate: soonest).save(on: app.db)
                try await Project(name: "Project due middle", dueDate: sooner).save(on: app.db)
                try await PCCTask(title: "Undated Task Two").save(on: app.db)
                try await Project(name: "Undated Project One").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/deadlines",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([DeadlineItemResponse].self)
                        #expect(body.map(\.title) == [
                            "Project due first",
                            "Project due middle",
                            "Task due last",
                            "Undated Project One",
                            "Undated Task Two",
                        ])
                        #expect(body.map(\.kind) == [.project, .project, .task, .project, .task])
                        #expect(body.last?.dueDate == nil)
                        #expect(body.first?.dueDate == soonest)
                    }
                )
            }
        }

        // MARK: - Courses (ticket #20)

        @Test("GET /v1/deadlines includes a Course's own Deadline")
        func listsCourseDeadlines() async throws {
            try await withDeadlinesApp { app in
                let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
                try await Course(name: "CS 301", termMonth: 9, termYear: 2026, dueDate: dueDate).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/deadlines",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([DeadlineItemResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.kind == .course)
                        #expect(body.first?.title == "CS 301")
                        #expect(body.first?.dueDate == dueDate)
                        #expect(body.first?.isComplete == nil)
                    }
                )
            }
        }

        @Test("GET /v1/deadlines includes a Course-scoped Task alongside the Course's own Deadline")
        func listsCourseScopedTaskAlongsideCourseDeadline() async throws {
            try await withDeadlinesApp { app in
                let taskDue = Date(timeIntervalSince1970: 1_600_000_000)
                let courseDue = Date(timeIntervalSince1970: 1_700_000_000)
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026, dueDate: courseDue)
                try await course.save(on: app.db)
                try await PCCTask(title: "Problem set", dueDate: taskDue, courseID: try course.requireID()).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/deadlines",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([DeadlineItemResponse].self)
                        #expect(body.map(\.title) == ["Problem set", "CS 301"])
                        #expect(body.map(\.kind) == [.task, .course])
                    }
                )
            }
        }
    }
}
