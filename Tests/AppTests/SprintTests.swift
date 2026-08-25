import Testing
import VaporTesting

@testable import App

/// Same seam as `ClientTests`/`TaskTests`: real HTTP requests against a
/// running Vapor app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Sprints", .serialized)
    struct SprintTests {
        @discardableResult
        private func withSprintsApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await PCCTask.query(on: app.db).delete()
                try await Sprint.query(on: app.db).delete()
                try await Project.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        private func makeDates() -> (start: Date, end: Date) {
            let start = Date()
            let end = start.addingTimeInterval(60 * 60 * 24 * 14)
            return (start, end)
        }

        @Test("rejects requests without a bearer token")
        func sprintsWithoutTokenAreRejected() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/sprints?projectID=\(try project.requireID())",
                    afterResponse: { res async in
                        #expect(res.status == .unauthorized)
                    }
                )
            }
        }

        @Test("creates a Sprint with a name, startDate, and endDate within a Project")
        func createsASprint() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let projectID = try project.requireID()
                let (start, end) = makeDates()

                try await app.testing().test(
                    .POST, "/v1/sprints",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveSprintRequest(projectID: projectID, name: "Sprint 1", startDate: start, endDate: end))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(SprintResponse.self)
                        #expect(body.name == "Sprint 1")
                        #expect(body.projectID == projectID)
                        #expect(abs(body.startDate.timeIntervalSince1970 - start.timeIntervalSince1970) < 1)
                        #expect(abs(body.endDate.timeIntervalSince1970 - end.timeIntervalSince1970) < 1)
                    }
                )

                let stored = try await Sprint.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.name == "Sprint 1")
            }
        }

        @Test("rejects creating a Sprint with an empty or whitespace-only name")
        func rejectsEmptySprintName() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let (start, end) = makeDates()

                try await app.testing().test(
                    .POST, "/v1/sprints",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveSprintRequest(projectID: try project.requireID(), name: "   ", startDate: start, endDate: end)
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Sprint.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects creating a Sprint with a nonexistent projectID")
        func rejectsMissingProjectOnCreate() async throws {
            try await withSprintsApp { app in
                let (start, end) = makeDates()

                try await app.testing().test(
                    .POST, "/v1/sprints",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveSprintRequest(projectID: UUID(), name: "Sprint 1", startDate: start, endDate: end))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("rejects creating a Sprint whose endDate is before its startDate")
        func rejectsBackwardsDateRange() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let (start, end) = makeDates()

                try await app.testing().test(
                    .POST, "/v1/sprints",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveSprintRequest(projectID: try project.requireID(), name: "Backwards", startDate: end, endDate: start)
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("edits a Sprint's name and dates")
        func editsASprint() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let (start, end) = makeDates()
                let sprint = Sprint(name: "Original", startDate: start, endDate: end, projectID: try project.requireID())
                try await sprint.save(on: app.db)
                let id = try sprint.requireID()
                let newStart = start.addingTimeInterval(60 * 60 * 24)
                let newEnd = end.addingTimeInterval(60 * 60 * 24)

                try await app.testing().test(
                    .PUT, "/v1/sprints/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(UpdateSprintRequest(name: "Renamed", startDate: newStart, endDate: newEnd))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(SprintResponse.self)
                        #expect(body.name == "Renamed")
                        #expect(abs(body.startDate.timeIntervalSince1970 - newStart.timeIntervalSince1970) < 1)
                        #expect(abs(body.endDate.timeIntervalSince1970 - newEnd.timeIntervalSince1970) < 1)
                    }
                )

                let stored = try await Sprint.find(id, on: app.db)
                #expect(stored?.name == "Renamed")
            }
        }

        @Test("deletes a Sprint; its Tasks become Sprint-less rather than deleted")
        func deletingSprintDetachesItsTasks() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let projectID = try project.requireID()
                let (start, end) = makeDates()
                let sprint = Sprint(name: "Doomed", startDate: start, endDate: end, projectID: projectID)
                try await sprint.save(on: app.db)
                let sprintID = try sprint.requireID()
                let task = PCCTask(title: "Survivor", projectID: projectID, sprintID: sprintID)
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/sprints/\(sprintID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PCCTask.find(taskID, on: app.db)
                #expect(stored != nil)
                #expect(stored?.$sprint.id == nil)
            }
        }

        @Test("deleting a Sprint that doesn't exist 404s")
        func deletingMissingSprintFails() async throws {
            try await withSprintsApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/sprints/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("lists Sprints scoped to one Project")
        func listsSprintsScopedToProject() async throws {
            try await withSprintsApp { app in
                let projectA = Project(name: "Alpha")
                let projectB = Project(name: "Beta")
                try await projectA.save(on: app.db)
                try await projectB.save(on: app.db)
                let projectAID = try projectA.requireID()
                let (start, end) = makeDates()
                try await Sprint(name: "In Alpha", startDate: start, endDate: end, projectID: projectAID).save(on: app.db)
                try await Sprint(name: "In Beta", startDate: start, endDate: end, projectID: try projectB.requireID()).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/sprints?projectID=\(projectAID)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([SprintResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.name == "In Alpha")
                    }
                )
            }
        }

        @Test("listing Sprints without a projectID 400s")
        func listingSprintsWithoutProjectIDFails() async throws {
            try await withSprintsApp { app in
                try await app.testing().test(
                    .GET, "/v1/sprints",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("listing Sprints with a malformed projectID 400s")
        func listingSprintsWithMalformedProjectIDFails() async throws {
            try await withSprintsApp { app in
                try await app.testing().test(
                    .GET, "/v1/sprints?projectID=not-a-uuid",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("assigns a Task to a Sprint, moves it to another, then removes it (Sprint-less)")
        func reassignsTaskSprint() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let projectID = try project.requireID()
                let (start, end) = makeDates()
                let sprintA = Sprint(name: "Sprint A", startDate: start, endDate: end, projectID: projectID)
                let sprintB = Sprint(name: "Sprint B", startDate: start, endDate: end, projectID: projectID)
                try await sprintA.save(on: app.db)
                try await sprintB.save(on: app.db)
                let task = PCCTask(title: "Movable", projectID: projectID)
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/sprint",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskSprintRequest(sprintID: try sprintA.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.sprintID == sprintA.id)
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/sprint",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskSprintRequest(sprintID: try sprintB.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.sprintID == sprintB.id)
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/sprint",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskSprintRequest(sprintID: nil))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.sprintID == nil)
                    }
                )
            }
        }

        @Test("assigning a Task to a Sprint that doesn't exist fails")
        func assigningMissingSprintFails() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let task = PCCTask(title: "Orphan candidate", projectID: try project.requireID())
                try await task.save(on: app.db)
                let id = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)/sprint",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskSprintRequest(sprintID: UUID()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("assigning a Task a Sprint that doesn't belong to its current Project fails")
        func assigningSprintFromOtherProjectFails() async throws {
            try await withSprintsApp { app in
                let projectA = Project(name: "Alpha")
                let projectB = Project(name: "Beta")
                try await projectA.save(on: app.db)
                try await projectB.save(on: app.db)
                let (start, end) = makeDates()
                let sprintB = Sprint(name: "In Beta", startDate: start, endDate: end, projectID: try projectB.requireID())
                try await sprintB.save(on: app.db)
                let task = PCCTask(title: "In Alpha", projectID: try projectA.requireID())
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/sprint",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskSprintRequest(sprintID: try sprintB.requireID()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("assigning a Sprint to a Project-less Task fails")
        func assigningSprintToProjectLessTaskFails() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let (start, end) = makeDates()
                let sprint = Sprint(name: "Sprint", startDate: start, endDate: end, projectID: try project.requireID())
                try await sprint.save(on: app.db)
                let task = PCCTask(title: "Project-less")
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/sprint",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskSprintRequest(sprintID: try sprint.requireID()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("moving a Task to a different Project clears a Sprint that belonged to the old Project")
        func movingTaskToDifferentProjectClearsSprint() async throws {
            try await withSprintsApp { app in
                let projectA = Project(name: "Alpha")
                let projectB = Project(name: "Beta")
                try await projectA.save(on: app.db)
                try await projectB.save(on: app.db)
                let projectAID = try projectA.requireID()
                let (start, end) = makeDates()
                let sprintA = Sprint(name: "In Alpha", startDate: start, endDate: end, projectID: projectAID)
                try await sprintA.save(on: app.db)
                let task = PCCTask(title: "Movable", projectID: projectAID, sprintID: try sprintA.requireID())
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/project",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskProjectRequest(projectID: try projectB.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.projectID == projectB.id)
                        #expect(body.sprintID == nil)
                    }
                )

                let stored = try await PCCTask.find(taskID, on: app.db)
                #expect(stored?.$sprint.id == nil)
            }
        }

        @Test("moving a Task to the same Project it's already in does not clear its Sprint")
        func movingTaskToSameProjectKeepsSprint() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let projectID = try project.requireID()
                let (start, end) = makeDates()
                let sprint = Sprint(name: "In Alpha", startDate: start, endDate: end, projectID: projectID)
                try await sprint.save(on: app.db)
                let sprintID = try sprint.requireID()
                let task = PCCTask(title: "Stationary", projectID: projectID, sprintID: sprintID)
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/project",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskProjectRequest(projectID: projectID))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.projectID == projectID)
                        #expect(body.sprintID == sprintID)
                    }
                )

                let stored = try await PCCTask.find(taskID, on: app.db)
                #expect(stored?.$sprint.id == sprintID)
            }
        }

        @Test("GET /v1/tasks?sprintID= lists only that Sprint's Tasks; ?projectID= still lists every Task in the Project")
        func listsTasksScopedToSprintAndProject() async throws {
            try await withSprintsApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                let projectID = try project.requireID()
                let (start, end) = makeDates()
                let sprint = Sprint(name: "Sprint 1", startDate: start, endDate: end, projectID: projectID)
                try await sprint.save(on: app.db)
                let sprintID = try sprint.requireID()
                try await PCCTask(title: "In Sprint", projectID: projectID, sprintID: sprintID).save(on: app.db)
                try await PCCTask(title: "In Project only", projectID: projectID).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/tasks?sprintID=\(sprintID)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TaskResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.title == "In Sprint")
                    }
                )

                try await app.testing().test(
                    .GET, "/v1/tasks?projectID=\(projectID)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TaskResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.title)) == ["In Sprint", "In Project only"])
                    }
                )
            }
        }
    }
}
