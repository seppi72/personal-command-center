import Testing
import VaporTesting

@testable import App

/// Ticket #20: Project/Course exclusivity (ADR-0003) and Course-deletion
/// orphaning — the cross-cutting behavior that spans `TaskController` and
/// `CourseController`, the same reason `SprintTests` (not `TaskTests`) is
/// where Task↔Sprint↔Project cross-clearing lives.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows —
// including with `TaskTests`/`SprintTests`/`CourseTests`, which share these
// same tables.
extension AppTestSuite {
    @Suite("Task-Course assignment + Project/Course exclusivity", .serialized)
    struct CourseTaskTests {
        @discardableResult
        private func withCourseTaskApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await PCCTask.query(on: app.db).delete()
                try await Sprint.query(on: app.db).delete()
                try await Project.query(on: app.db).delete()
                try await Course.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("assigning a Course to a Task that currently has a Project clears the Project")
        func assigningCourseClearsProject() async throws {
            try await withCourseTaskApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let task = PCCTask(title: "Switching", projectID: try project.requireID())
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/course",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskCourseRequest(courseID: try course.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.courseID == course.id)
                        #expect(body.projectID == nil)
                    }
                )

                let stored = try await PCCTask.find(taskID, on: app.db)
                #expect(stored?.$project.id == nil)
            }
        }

        @Test("assigning a Course to a Task clears a Sprint that implied the old Project")
        func assigningCourseClearsSprint() async throws {
            try await withCourseTaskApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let projectID = try project.requireID()
                let sprint = Sprint(name: "Sprint 1", startDate: Date(), endDate: Date().addingTimeInterval(60 * 60 * 24 * 7), projectID: projectID)
                try await sprint.save(on: app.db)
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let task = PCCTask(title: "Sprinting", projectID: projectID, sprintID: try sprint.requireID())
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/course",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskCourseRequest(courseID: try course.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.sprintID == nil)
                    }
                )

                let stored = try await PCCTask.find(taskID, on: app.db)
                #expect(stored?.$sprint.id == nil)
            }
        }

        @Test("assigning a Project to a Task that currently has a Course clears the Course")
        func assigningProjectClearsCourse() async throws {
            try await withCourseTaskApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let task = PCCTask(title: "Switching", courseID: try course.requireID())
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/project",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskProjectRequest(projectID: try project.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.projectID == project.id)
                        #expect(body.courseID == nil)
                    }
                )

                let stored = try await PCCTask.find(taskID, on: app.db)
                #expect(stored?.$course.id == nil)
            }
        }

        @Test("removing a Task's Project leaves it Course-less, not implicitly Coursed")
        func removingProjectLeavesCourseUntouched() async throws {
            try await withCourseTaskApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let task = PCCTask(title: "Freeing up", projectID: try project.requireID())
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/project",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskProjectRequest(projectID: nil))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.projectID == nil)
                        #expect(body.courseID == nil)
                    }
                )
            }
        }

        @Test("deleting a Course makes its Tasks Course-less rather than deleting them")
        func deletingCourseDetachesItsTasks() async throws {
            try await withCourseTaskApp { app in
                let course = Course(name: "Doomed", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let courseID = try course.requireID()
                let task = PCCTask(title: "Survivor", courseID: courseID)
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/courses/\(courseID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PCCTask.find(taskID, on: app.db)
                #expect(stored != nil)
                #expect(stored?.$course.id == nil)
            }
        }
    }
}
