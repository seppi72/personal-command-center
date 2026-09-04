import Testing
import VaporTesting

@testable import App

/// Same seam as `ClientTests`/`ProjectTests`: real HTTP requests against a
/// running Vapor app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Courses", .serialized)
    struct CourseTests {
        @discardableResult
        private func withCoursesApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await TimeEntry.query(on: app.db).delete()
                try await PersonalCommitment.query(on: app.db).delete()
                try await Course.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("rejects requests without a bearer token")
        func coursesWithoutTokenAreRejected() async throws {
            try await withCoursesApp { app in
                try await app.testing().test(.GET, "/v1/courses", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Course with a name, termMonth, and termYear")
        func createsACourse() async throws {
            try await withCoursesApp { app in
                try await app.testing().test(
                    .POST, "/v1/courses",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "CS 301", termMonth: 9, termYear: 2026))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CourseResponse.self)
                        #expect(body.name == "CS 301")
                        #expect(body.termMonth == 9)
                        #expect(body.termYear == 2026)
                        #expect(body.dueDate == nil)
                    }
                )

                let stored = try await Course.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.name == "CS 301")
            }
        }

        @Test("a newly-created Course has no Deadline by default")
        func newCourseHasNoDeadline() async throws {
            try await withCoursesApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                #expect(course.dueDate == nil)
            }
        }

        @Test("rejects creating a Course with an empty or whitespace-only name")
        func rejectsEmptyCourseName() async throws {
            try await withCoursesApp { app in
                try await app.testing().test(
                    .POST, "/v1/courses",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "   ", termMonth: 9, termYear: 2026))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Course.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects an out-of-range termMonth", arguments: [0, 13])
        func rejectsOutOfRangeTermMonth(termMonth: Int) async throws {
            try await withCoursesApp { app in
                try await app.testing().test(
                    .POST, "/v1/courses",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "CS 301", termMonth: termMonth, termYear: 2026))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Course.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects a non-positive termYear")
        func rejectsNonPositiveTermYear() async throws {
            try await withCoursesApp { app in
                try await app.testing().test(
                    .POST, "/v1/courses",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "CS 301", termMonth: 9, termYear: 0))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Course.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("lists all Courses")
        func listsAllCourses() async throws {
            try await withCoursesApp { app in
                try await Course(name: "CS 301", termMonth: 9, termYear: 2026).save(on: app.db)
                try await Course(name: "MATH 210", termMonth: 1, termYear: 2027).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/courses",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([CourseResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.name)) == ["CS 301", "MATH 210"])
                    }
                )
            }
        }

        @Test("edits a Course's name and term")
        func editsACourse() async throws {
            try await withCoursesApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let id = try course.requireID()

                try await app.testing().test(
                    .PUT, "/v1/courses/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "CS 301: Renamed", termMonth: 1, termYear: 2027))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CourseResponse.self)
                        #expect(body.name == "CS 301: Renamed")
                        #expect(body.termMonth == 1)
                        #expect(body.termYear == 2027)
                    }
                )

                let stored = try await Course.find(id, on: app.db)
                #expect(stored?.name == "CS 301: Renamed")
                #expect(stored?.termMonth == 1)
                #expect(stored?.termYear == 2027)
            }
        }

        @Test("editing a Course that doesn't exist 404s")
        func editingMissingCourseFails() async throws {
            try await withCoursesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/courses/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "Doesn't matter", termMonth: 9, termYear: 2026))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Course")
        func deletesACourse() async throws {
            try await withCoursesApp { app in
                let course = Course(name: "Throwaway", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let id = try course.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/courses/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Course.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("rejects deleting a Course a Time Entry still references")
        func deletingCourseWithReferencingTimeEntryFails() async throws {
            try await withCoursesApp { app in
                let course = Course(name: "Referenced", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let id = try course.requireID()
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                try await TimeEntry(
                    startDate: start, endDate: start.addingTimeInterval(3600), container: .course(id)
                ).save(on: app.db)

                try await app.testing().test(
                    .DELETE, "/v1/courses/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Course.find(id, on: app.db)
                #expect(stored != nil)
            }
        }

        @Test("rejects deleting a Course a Personal Commitment still references")
        func deletingCourseWithReferencingCommitmentFails() async throws {
            try await withCoursesApp { app in
                let course = Course(name: "Referenced", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let id = try course.requireID()
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                try await PersonalCommitment(
                    title: "Lecture",
                    startDate: start,
                    endDate: start.addingTimeInterval(3600),
                    courseID: id
                ).save(on: app.db)

                try await app.testing().test(
                    .DELETE, "/v1/courses/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Course.find(id, on: app.db)
                #expect(stored != nil)
            }
        }

        @Test("deleting a Course that doesn't exist 404s")
        func deletingMissingCourseFails() async throws {
            try await withCoursesApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/courses/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("attaches a Deadline to a Course, changes it, then removes it")
        func attachesChangesAndRemovesCourseDeadline() async throws {
            try await withCoursesApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let id = try course.requireID()

                let firstDueDate = Date(timeIntervalSince1970: 1_800_000_000)
                try await app.testing().test(
                    .PUT, "/v1/courses/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetCourseDeadlineRequest(dueDate: firstDueDate))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CourseResponse.self)
                        #expect(body.dueDate == firstDueDate)
                    }
                )

                let secondDueDate = Date(timeIntervalSince1970: 1_900_000_000)
                try await app.testing().test(
                    .PUT, "/v1/courses/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetCourseDeadlineRequest(dueDate: secondDueDate))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CourseResponse.self)
                        #expect(body.dueDate == secondDueDate)
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/courses/\(id)/deadline",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetCourseDeadlineRequest(dueDate: nil))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CourseResponse.self)
                        #expect(body.dueDate == nil)
                    }
                )
            }
        }

        @Test("rejects deleting a Course a Project still belongs to (ADR-0011)")
        func deletingCourseWithReferencingProjectFails() async throws {
            try await withCoursesApp { app in
                let course = Course(name: "Referenced", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let id = try course.requireID()
                let project = Project(name: "Group assignment", courseID: id)
                try await project.save(on: app.db)

                try await app.testing().test(
                    .DELETE, "/v1/courses/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Course.find(id, on: app.db)
                #expect(stored != nil)

                try await project.delete(on: app.db)
            }
        }
    }
}
