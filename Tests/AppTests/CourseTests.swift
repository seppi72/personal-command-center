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

        @Test("creates a Course with a name and a Term")
        func createsACourse() async throws {
            try await withCoursesApp { app in
                let term = try await makeTerm(on: app.db, year: 2026, semester: .first)
                let termID = try term.requireID()
                try await app.testing().test(
                    .POST, "/v1/courses",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "CS 301", termID: termID))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CourseResponse.self)
                        #expect(body.name == "CS 301")
                        #expect(body.termID == termID)
                        // The whole Term rides along, so a client listing
                        // Courses can label them without a second fetch.
                        #expect(body.term.displayName == "1st Semester 2026")
                        #expect(body.dueDate == nil)
                    }
                )

                let stored = try await Course.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.name == "CS 301")
                #expect(stored.first?.$term.id == termID)
            }
        }

        @Test("rejects creating a Course against a Term that doesn't exist")
        func rejectsUnknownTerm() async throws {
            try await withCoursesApp { app in
                try await app.testing().test(
                    .POST, "/v1/courses",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "CS 301", termID: UUID()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Course.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("a newly-created Course has no Deadline by default")
        func newCourseHasNoDeadline() async throws {
            try await withCoursesApp { app in
                let course = try await makeCourse(name: "CS 301", on: app.db)
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
                        let termID = try await makeTerm(on: app.db).requireID()
                        try req.content.encode(SaveCourseRequest(name: "   ", termID: termID))
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
                _ = try await makeCourse(name: "CS 301", on: app.db)
                _ = try await makeCourse(name: "MATH 210", on: app.db)

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
                let course = try await makeCourse(name: "CS 301", on: app.db)
                let id = try course.requireID()
                let otherTermID = try await makeTerm(on: app.db, year: 2027, semester: .second)
                    .requireID()

                try await app.testing().test(
                    .PUT, "/v1/courses/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "CS 301: Renamed", termID: otherTermID))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CourseResponse.self)
                        #expect(body.name == "CS 301: Renamed")
                        #expect(body.termID == otherTermID)
                        #expect(body.term.displayName == "2nd Semester 2027")
                    }
                )

                let stored = try await Course.find(id, on: app.db)
                #expect(stored?.name == "CS 301: Renamed")
                #expect(stored?.$term.id == otherTermID)
            }
        }

        @Test("editing a Course that doesn't exist 404s")
        func editingMissingCourseFails() async throws {
            try await withCoursesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/courses/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCourseRequest(name: "Doesn't matter", termID: UUID()))
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
                let course = try await makeCourse(name: "Throwaway", on: app.db)
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
                let course = try await makeCourse(name: "Referenced", on: app.db)
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
                let course = try await makeCourse(name: "Referenced", on: app.db)
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
                let course = try await makeCourse(name: "CS 301", on: app.db)
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
                let course = try await makeCourse(name: "Referenced", on: app.db)
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
