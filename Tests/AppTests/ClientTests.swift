import Testing
import VaporTesting

@testable import App

/// Same seam as `ProjectTests`: real HTTP requests against a running Vapor
/// app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Clients", .serialized)
    struct ClientTests {
        @discardableResult
        private func withClientsApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await Project.query(on: app.db).delete()
                try await PCCClient.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("rejects requests without a bearer token")
        func clientsWithoutTokenAreRejected() async throws {
            try await withClientsApp { app in
                try await app.testing().test(.GET, "/v1/clients", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Client with a name")
        func createsAClient() async throws {
            try await withClientsApp { app in
                try await app.testing().test(
                    .POST, "/v1/clients",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveClientRequest(name: "Acme Corp"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(PCCClientResponse.self)
                        #expect(body.name == "Acme Corp")
                    }
                )

                let stored = try await PCCClient.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.name == "Acme Corp")
            }
        }

        @Test("rejects creating a Client with an empty or whitespace-only name")
        func rejectsEmptyClientName() async throws {
            try await withClientsApp { app in
                try await app.testing().test(
                    .POST, "/v1/clients",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveClientRequest(name: "   "))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await PCCClient.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects a malformed Client id")
        func rejectsMalformedClientID() async throws {
            try await withClientsApp { app in
                try await app.testing().test(
                    .PUT, "/v1/clients/not-a-uuid",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveClientRequest(name: "Doesn't matter"))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("lists all Clients")
        func listsAllClients() async throws {
            try await withClientsApp { app in
                try await PCCClient(name: "Alpha Inc").save(on: app.db)
                try await PCCClient(name: "Beta LLC").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/clients",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([PCCClientResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.name)) == ["Alpha Inc", "Beta LLC"])
                    }
                )
            }
        }

        @Test("edits a Client's name")
        func editsAClientName() async throws {
            try await withClientsApp { app in
                let client = PCCClient(name: "Original")
                try await client.save(on: app.db)
                let id = try client.requireID()

                try await app.testing().test(
                    .PUT, "/v1/clients/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveClientRequest(name: "Renamed"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(PCCClientResponse.self)
                        #expect(body.name == "Renamed")
                    }
                )

                let stored = try await PCCClient.find(id, on: app.db)
                #expect(stored?.name == "Renamed")
            }
        }

        @Test("editing a Client that doesn't exist 404s")
        func editingMissingClientFails() async throws {
            try await withClientsApp { app in
                try await app.testing().test(
                    .PUT, "/v1/clients/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveClientRequest(name: "Doesn't matter"))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Client")
        func deletesAClient() async throws {
            try await withClientsApp { app in
                let client = PCCClient(name: "Throwaway")
                try await client.save(on: app.db)
                let id = try client.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/clients/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PCCClient.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting a Client that doesn't exist 404s")
        func deletingMissingClientFails() async throws {
            try await withClientsApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/clients/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("assigns a Project to a Client, moves it to another, then removes it (Client-less)")
        func reassignsProjectClient() async throws {
            try await withClientsApp { app in
                let clientA = PCCClient(name: "Alpha Inc")
                let clientB = PCCClient(name: "Beta LLC")
                try await clientA.save(on: app.db)
                try await clientB.save(on: app.db)
                let project = Project(name: "Movable")
                try await project.save(on: app.db)
                let projectID = try project.requireID()

                try await app.testing().test(
                    .PUT, "/v1/projects/\(projectID)/client",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectClientRequest(clientID: try clientA.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.clientID == clientA.id)
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/projects/\(projectID)/client",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectClientRequest(clientID: try clientB.requireID()))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.clientID == clientB.id)
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/projects/\(projectID)/client",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectClientRequest(clientID: nil))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectResponse.self)
                        #expect(body.clientID == nil)
                    }
                )
            }
        }

        @Test("assigning a Project to a Client that doesn't exist fails")
        func assigningMissingClientFails() async throws {
            try await withClientsApp { app in
                let project = Project(name: "Orphan candidate")
                try await project.save(on: app.db)
                let id = try project.requireID()

                try await app.testing().test(
                    .PUT, "/v1/projects/\(id)/client",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SetProjectClientRequest(clientID: UUID()))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("deleting a Client makes its Projects Client-less rather than deleting them")
        func deletingClientDetachesItsProjects() async throws {
            try await withClientsApp { app in
                let client = PCCClient(name: "Doomed")
                try await client.save(on: app.db)
                let clientID = try client.requireID()
                let project = Project(name: "Survivor", clientID: clientID)
                try await project.save(on: app.db)
                let projectID = try project.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/clients/\(clientID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Project.find(projectID, on: app.db)
                #expect(stored != nil)
                #expect(stored?.$client.id == nil)
            }
        }

        @Test("lists all Projects regardless of Client")
        func listsAllProjectsRegardlessOfClient() async throws {
            try await withClientsApp { app in
                let client = PCCClient(name: "Alpha Inc")
                try await client.save(on: app.db)
                try await Project(name: "With a Client", clientID: try client.requireID()).save(on: app.db)
                try await Project(name: "Client-less").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/projects",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([ProjectResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.name)) == ["With a Client", "Client-less"])
                    }
                )
            }
        }

        @Test("lists Projects scoped to one Client")
        func listsProjectsScopedToClient() async throws {
            try await withClientsApp { app in
                let clientA = PCCClient(name: "Alpha Inc")
                let clientB = PCCClient(name: "Beta LLC")
                try await clientA.save(on: app.db)
                try await clientB.save(on: app.db)
                let clientAID = try clientA.requireID()
                try await Project(name: "For Alpha", clientID: clientAID).save(on: app.db)
                try await Project(name: "For Beta", clientID: try clientB.requireID()).save(on: app.db)
                try await Project(name: "Client-less").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/projects?clientID=\(clientAID)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([ProjectResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.name == "For Alpha")
                    }
                )
            }
        }
    }
}
