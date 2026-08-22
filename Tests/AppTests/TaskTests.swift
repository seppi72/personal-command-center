import Testing
import VaporTesting

@testable import App

/// Same seam as `ProjectTests`: real HTTP requests against a running Vapor
/// app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Tasks", .serialized)
    struct TaskTests {
        @discardableResult
        private func withTasksApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await PCCTask.query(on: app.db).delete()
                try await Project.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("rejects requests without a bearer token")
        func tasksWithoutTokenAreRejected() async throws {
            try await withTasksApp { app in
                try await app.testing().test(.GET, "/v1/tasks", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Task with a title, Project-less by default")
        func createsATask() async throws {
            try await withTasksApp { app in
                try await app.testing().test(
                    .POST, "/v1/tasks",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTaskRequest(title: "Write the ticket", notes: nil))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.title == "Write the ticket")
                        #expect(body.notes == nil)
                        #expect(body.isComplete == false)
                        #expect(body.projectID == nil)
                    }
                )

                let stored = try await PCCTask.query(on: app.db).all()
                #expect(stored.count == 1)
            }
        }

        @Test("creates a Task with optional notes")
        func createsATaskWithNotes() async throws {
            try await withTasksApp { app in
                try await app.testing().test(
                    .POST, "/v1/tasks",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTaskRequest(title: "Ship it", notes: "Don't forget the CHANGELOG"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.notes == "Don't forget the CHANGELOG")
                    }
                )
            }
        }

        @Test("rejects creating a Task with an empty or whitespace-only title")
        func rejectsEmptyTaskTitle() async throws {
            try await withTasksApp { app in
                try await app.testing().test(
                    .POST, "/v1/tasks",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTaskRequest(title: "   ", notes: nil))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await PCCTask.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("edits a Task's title and notes")
        func editsATask() async throws {
            try await withTasksApp { app in
                let task = PCCTask(title: "Original", notes: "Original notes")
                try await task.save(on: app.db)
                let id = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTaskRequest(title: "Renamed", notes: "New notes"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.title == "Renamed")
                        #expect(body.notes == "New notes")
                    }
                )

                let stored = try await PCCTask.find(id, on: app.db)
                #expect(stored?.title == "Renamed")
                #expect(stored?.notes == "New notes")
            }
        }

        @Test("rejects editing a Task with an empty or whitespace-only title")
        func rejectsEmptyTaskTitleOnEdit() async throws {
            try await withTasksApp { app in
                let task = PCCTask(title: "Original")
                try await task.save(on: app.db)
                let id = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTaskRequest(title: "   ", notes: nil))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await PCCTask.find(id, on: app.db)
                #expect(stored?.title == "Original")
            }
        }

        @Test("rejects a malformed Task id")
        func rejectsMalformedTaskID() async throws {
            try await withTasksApp { app in
                try await app.testing().test(
                    .PUT, "/v1/tasks/not-a-uuid",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTaskRequest(title: "Doesn't matter", notes: nil))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("editing a Task that doesn't exist 404s")
        func editingMissingTaskFails() async throws {
            try await withTasksApp { app in
                try await app.testing().test(
                    .PUT, "/v1/tasks/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTaskRequest(title: "Doesn't matter", notes: nil))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Task")
        func deletesATask() async throws {
            try await withTasksApp { app in
                let task = PCCTask(title: "Throwaway")
                try await task.save(on: app.db)
                let id = try task.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/tasks/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PCCTask.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting a Task that doesn't exist 404s")
        func deletingMissingTaskFails() async throws {
            try await withTasksApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/tasks/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("marks a Task complete, then incomplete")
        func togglesTaskCompletion() async throws {
            try await withTasksApp { app in
                let task = PCCTask(title: "Finish this")
                try await task.save(on: app.db)
                let id = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)/complete",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.isComplete == true)
                    }
                )
                #expect(try await PCCTask.find(id, on: app.db)?.isComplete == true)

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)/incomplete",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.isComplete == false)
                    }
                )
                #expect(try await PCCTask.find(id, on: app.db)?.isComplete == false)
            }
        }

        @Test("marking a Task complete that doesn't exist 404s")
        func markingMissingTaskCompleteFails() async throws {
            try await withTasksApp { app in
                try await app.testing().test(
                    .PUT, "/v1/tasks/\(UUID())/complete",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("assigns a Task to a Project, moves it to another, then removes it (Project-less)")
        func reassignsTaskProject() async throws {
            try await withTasksApp { app in
                let projectA = Project(name: "Alpha")
                let projectB = Project(name: "Beta")
                try await projectA.save(on: app.db)
                try await projectB.save(on: app.db)
                let task = PCCTask(title: "Movable")
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(taskID)/project",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskProjectRequest(projectID: try projectA.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TaskResponse.self)
                        #expect(body.projectID == projectA.id)
                    }
                )

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
                    }
                )

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
                    }
                )
            }
        }

        @Test("assigning a Task to a Project that doesn't exist fails")
        func assigningMissingProjectFails() async throws {
            try await withTasksApp { app in
                let task = PCCTask(title: "Orphan candidate")
                try await task.save(on: app.db)
                let id = try task.requireID()

                try await app.testing().test(
                    .PUT, "/v1/tasks/\(id)/project",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(AssignTaskProjectRequest(projectID: UUID()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("deleting a Project makes its Tasks Project-less rather than deleting them")
        func deletingProjectDetachesItsTasks() async throws {
            try await withTasksApp { app in
                let project = Project(name: "Doomed")
                try await project.save(on: app.db)
                let projectID = try project.requireID()
                let task = PCCTask(title: "Survivor", projectID: projectID)
                try await task.save(on: app.db)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/projects/\(projectID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PCCTask.find(taskID, on: app.db)
                #expect(stored != nil)
                #expect(stored?.$project.id == nil)
            }
        }

        @Test("lists all Tasks regardless of Project")
        func listsAllTasks() async throws {
            try await withTasksApp { app in
                let project = Project(name: "Alpha")
                try await project.save(on: app.db)
                try await PCCTask(title: "In a Project", projectID: try project.requireID()).save(on: app.db)
                try await PCCTask(title: "Project-less").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/tasks",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TaskResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.title)) == ["In a Project", "Project-less"])
                    }
                )
            }
        }

        @Test("lists Tasks scoped to one Project")
        func listsTasksScopedToProject() async throws {
            try await withTasksApp { app in
                let projectA = Project(name: "Alpha")
                let projectB = Project(name: "Beta")
                try await projectA.save(on: app.db)
                try await projectB.save(on: app.db)
                let projectAID = try projectA.requireID()
                try await PCCTask(title: "In Alpha", projectID: projectAID).save(on: app.db)
                try await PCCTask(title: "In Beta", projectID: try projectB.requireID()).save(on: app.db)
                try await PCCTask(title: "Project-less").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/tasks?projectID=\(projectAID)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TaskResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.title == "In Alpha")
                    }
                )
            }
        }
    }
}
