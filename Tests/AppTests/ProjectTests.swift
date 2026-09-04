import Testing
import VaporTesting

@testable import App

/// Exercises the seam agreed in the spec: a real HTTP request against a
/// running Vapor app, backed by a real (test) Postgres database — no mocked
/// services, no reaching past the HTTP boundary.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Projects", .serialized)
    struct ProjectTests {
        @discardableResult
        private func withProjectsApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await TimeEntry.query(on: app.db).delete()
                try await Project.query(on: app.db).delete()
                try await Course.query(on: app.db).delete()
                try await PCCClient.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("rejects requests without a bearer token")
        func projectsWithoutTokenAreRejected() async throws {
            try await withProjectsApp { app in
                try await app.testing().test(.GET, "/v1/projects", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Project with a name")
        func createsAProject() async throws {
            try await withProjectsApp { app in
                try await app.testing().test(
                    .POST, "/v1/projects",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveProjectRequest(name: "Command Center"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.name == "Command Center")
                    }
                )

                let stored = try await Project.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.name == "Command Center")
            }
        }

        @Test("rejects creating a Project with an empty or whitespace-only name")
        func rejectsEmptyProjectName() async throws {
            try await withProjectsApp { app in
                try await app.testing().test(
                    .POST, "/v1/projects",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveProjectRequest(name: "   "))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Project.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects a malformed Project id")
        func rejectsMalformedProjectID() async throws {
            try await withProjectsApp { app in
                try await app.testing().test(
                    .PUT, "/v1/projects/not-a-uuid",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveProjectRequest(name: "Doesn't matter"))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("lists all Projects")
        func listsAllProjects() async throws {
            try await withProjectsApp { app in
                try await Project(name: "Alpha").save(on: app.db)
                try await Project(name: "Beta").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/projects",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([ProjectResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.name)) == ["Alpha", "Beta"])
                    }
                )
            }
        }

        @Test("edits a Project's name")
        func editsAProjectName() async throws {
            try await withProjectsApp { app in
                let project = Project(name: "Original")
                try await project.save(on: app.db)
                let id = try project.requireID()

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveProjectRequest(name: "Renamed"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.name == "Renamed")
                    }
                )

                let stored = try await Project.find(id, on: app.db)
                #expect(stored?.name == "Renamed")
            }
        }

        @Test("editing a Project that doesn't exist 404s")
        func editingMissingProjectFails() async throws {
            try await withProjectsApp { app in
                try await app.testing().test(
                    .PUT, "/v1/projects/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveProjectRequest(name: "Doesn't matter"))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Project")
        func deletesAProject() async throws {
            try await withProjectsApp { app in
                let project = Project(name: "Throwaway")
                try await project.save(on: app.db)
                let id = try project.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/projects/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Project.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting a Project that doesn't exist 404s")
        func deletingMissingProjectFails() async throws {
            try await withProjectsApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/projects/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("rejects deleting a Project a Time Entry still references")
        func deletingProjectWithReferencingTimeEntryFails() async throws {
            try await withProjectsApp { app in
                let project = Project(name: "Referenced")
                try await project.save(on: app.db)
                let id = try project.requireID()
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                try await TimeEntry(
                    startDate: start, endDate: start.addingTimeInterval(3600), container: .project(id)
                ).save(on: app.db)

                try await app.testing().test(
                    .DELETE, "/v1/projects/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Project.find(id, on: app.db)
                #expect(stored != nil)
            }
        }

        @Test("assigns a Project to a Course, clearing any Client it had (ADR-0011)")
        func assigningCourseClearsClient() async throws {
            try await withProjectsApp { app in
                let client = PCCClient(name: "Acme")
                try await client.save(on: app.db)
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let project = Project(name: "Group assignment", clientID: try client.requireID())
                try await project.save(on: app.db)
                let id = try project.requireID()
                let courseID = try course.requireID()

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)/course",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectCourseRequest(courseID: courseID))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.courseID == courseID)
                        #expect(body.clientID == nil)
                    }
                )

                let stored = try await Project.find(id, on: app.db)
                #expect(stored?.$course.id == courseID)
                #expect(stored?.$client.id == nil)
            }
        }

        @Test("assigns a Project to a Client, clearing any Course it had (ADR-0011)")
        func assigningClientClearsCourse() async throws {
            try await withProjectsApp { app in
                let client = PCCClient(name: "Acme")
                try await client.save(on: app.db)
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let project = Project(name: "Group assignment", courseID: try course.requireID())
                try await project.save(on: app.db)
                let id = try project.requireID()
                let clientID = try client.requireID()

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)/client",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectClientRequest(clientID: clientID))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.clientID == clientID)
                        #expect(body.courseID == nil)
                    }
                )

                let stored = try await Project.find(id, on: app.db)
                #expect(stored?.$client.id == clientID)
                #expect(stored?.$course.id == nil)
            }
        }

        @Test("clearing a Project's Course leaves it parent-less rather than restoring a Client")
        func clearingCourseLeavesProjectParentless() async throws {
            try await withProjectsApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let project = Project(name: "Group assignment", courseID: try course.requireID())
                try await project.save(on: app.db)
                let id = try project.requireID()

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)/course",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectCourseRequest(courseID: nil))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.courseID == nil)
                        #expect(body.clientID == nil)
                    }
                )
            }
        }

        @Test("rejects assigning a Project to a Course that doesn't exist")
        func assigningMissingCourseFails() async throws {
            try await withProjectsApp { app in
                let project = Project(name: "Group assignment")
                try await project.save(on: app.db)
                let id = try project.requireID()

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)/course",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectCourseRequest(courseID: UUID()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("lists Projects scoped to one Course")
        func listsProjectsScopedToACourse() async throws {
            try await withProjectsApp { app in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let courseID = try course.requireID()
                try await Project(name: "Coursework", courseID: courseID).save(on: app.db)
                try await Project(name: "Unrelated").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/projects?courseID=\(courseID)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let body = try res.content.decode([ProjectResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.name == "Coursework")
                    }
                )
            }
        }

        @Test("no sequence of writes can leave a Project holding both parents (ADR-0011)")
        func aProjectNeverHoldsBothParents() async throws {
            try await withProjectsApp { app in
                let client = PCCClient(name: "Acme")
                try await client.save(on: app.db)
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let project = Project(name: "Group assignment")
                try await project.save(on: app.db)
                let id = try project.requireID()
                let clientID = try client.requireID()
                let courseID = try course.requireID()

                // Assign one parent, then the other, then back — the
                // closest the API comes to "save a Project with both", since
                // neither parent is settable in the same request.
                for _ in 0..<2 {
                    try await app.testing().test(
                        .PUT, "/v1/projects/\(id)/client",
                        headers: authHeaders(),
                        beforeRequest: { req async throws in
                            try req.content.encode(SetProjectClientRequest(clientID: clientID))
                        },
                        afterResponse: { res async throws in
                            let body = try res.content.decode(ProjectResponse.self)
                            #expect(body.clientID != nil)
                            #expect(body.courseID == nil)
                        }
                    )
                    try await app.testing().test(
                        .PUT, "/v1/projects/\(id)/course",
                        headers: authHeaders(),
                        beforeRequest: { req async throws in
                            try req.content.encode(SetProjectCourseRequest(courseID: courseID))
                        },
                        afterResponse: { res async throws in
                            let body = try res.content.decode(ProjectResponse.self)
                            #expect(body.courseID != nil)
                            #expect(body.clientID == nil)
                        }
                    )
                }

                let stored = try await Project.find(id, on: app.db)
                #expect(stored?.$client.id == nil)
                #expect(stored?.$course.id == courseID)
            }
        }

        @Test("setParent never leaves a Project with both a Client and a Course")
        func setParentKeepsParentsExclusive() throws {
            let clientID = UUID()
            let courseID = UUID()
            let project = Project(name: "Group assignment", clientID: clientID)

            project.setParent(.course(courseID))
            #expect(project.$client.id == nil)
            #expect(project.parent == .course(courseID))

            project.setParent(.client(clientID))
            #expect(project.$course.id == nil)
            #expect(project.parent == .client(clientID))

            project.setParent(.none)
            #expect(project.$client.id == nil)
            #expect(project.$course.id == nil)
            #expect(project.parent == .none)
        }
    }
}
