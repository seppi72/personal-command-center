import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `TaskTests`/`ClientTests`: real HTTP requests against a
/// running Vapor app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Time Entries", .serialized)
    struct TimeEntryTests {
        @discardableResult
        private func withTimeEntriesApp<T>(_ test: (Application) async throws -> T) async throws -> T {
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

        private func makeTask(_ app: Application, title: String = "Task") async throws -> PCCTask {
            let task = PCCTask(title: title)
            try await task.save(on: app.db)
            return task
        }

        private func makeProject(_ app: Application, name: String = "Project") async throws -> Project {
            let project = Project(name: name)
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

        @Test("rejects requests without a bearer token")
        func timeEntriesWithoutTokenAreRejected() async throws {
            try await withTimeEntriesApp { app in
                try await app.testing().test(.GET, "/v1/time-entries", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Time Entry attached to a Task")
        func createsATimeEntryOnATask() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let taskID = try task.requireID()
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = Date(timeIntervalSince1970: 1_800_003_600)

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: end, notes: "Wrote the ticket",
                            taskID: taskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse.self)
                        #expect(body.taskID == taskID)
                        #expect(body.projectID == nil)
                        #expect(body.clientID == nil)
                        #expect(body.courseID == nil)
                        #expect(body.notes == "Wrote the ticket")
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 1)
            }
        }

        @Test("creates a Time Entry attached to a Project, a Client, or a Course")
        func createsATimeEntryOnEachContainerKind() async throws {
            try await withTimeEntriesApp { app in
                let project = try await makeProject(app)
                let client = try await makeClient(app)
                let course = try await makeCourse(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start.addingTimeInterval(3600), notes: nil,
                            taskID: nil, projectID: try project.requireID(), clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse.self)
                        #expect(body.projectID == project.id)
                    }
                )

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start.addingTimeInterval(7200), endDate: start.addingTimeInterval(10800),
                            notes: nil, taskID: nil, projectID: nil, clientID: try client.requireID(), courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse.self)
                        #expect(body.clientID == client.id)
                    }
                )

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start.addingTimeInterval(14400), endDate: start.addingTimeInterval(18000),
                            notes: nil, taskID: nil, projectID: nil, clientID: nil, courseID: try course.requireID()
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse.self)
                        #expect(body.courseID == course.id)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 3)
            }
        }

        @Test("rejects creating a Time Entry with zero containers")
        func rejectsZeroContainers() async throws {
            try await withTimeEntriesApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start.addingTimeInterval(3600), notes: nil,
                            taskID: nil, projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects creating a Time Entry with more than one container")
        func rejectsMultipleContainers() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let project = try await makeProject(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start.addingTimeInterval(3600), notes: nil,
                            taskID: try task.requireID(), projectID: try project.requireID(),
                            clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects creating a Time Entry against a Task/Project/Client/Course that doesn't exist")
        func rejectsNonexistentContainer() async throws {
            try await withTimeEntriesApp { app in
                let start = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start.addingTimeInterval(3600), notes: nil,
                            taskID: UUID(), projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start.addingTimeInterval(3600), notes: nil,
                            taskID: nil, projectID: nil, clientID: nil, courseID: UUID()
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects creating a Time Entry whose endDate is not after startDate")
        func rejectsNonPositiveDuration() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start, notes: nil,
                            taskID: try task.requireID(), projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start.addingTimeInterval(-3600), notes: nil,
                            taskID: try task.requireID(), projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects creating a Time Entry whose span strictly overlaps an existing one")
        func rejectsOverlappingSpan() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let taskID = try task.requireID()
                let existingStart = Date(timeIntervalSince1970: 1_800_000_000)
                let existingEnd = existingStart.addingTimeInterval(3600)
                try await TimeEntry(
                    startDate: existingStart, endDate: existingEnd, container: .task(taskID)
                ).save(on: app.db)

                // Overlaps: starts before the existing entry ends and ends
                // after it starts.
                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: existingStart.addingTimeInterval(1800),
                            endDate: existingEnd.addingTimeInterval(1800),
                            notes: nil, taskID: taskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 1)
            }
        }

        @Test("allows a new Time Entry whose span only touches an existing one's boundary")
        func allowsTouchingBoundary() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let taskID = try task.requireID()
                let existingStart = Date(timeIntervalSince1970: 1_800_000_000)
                let existingEnd = existingStart.addingTimeInterval(3600)
                try await TimeEntry(
                    startDate: existingStart, endDate: existingEnd, container: .task(taskID)
                ).save(on: app.db)

                // Starts exactly when the existing entry ends — touching,
                // not overlapping.
                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: existingEnd, endDate: existingEnd.addingTimeInterval(3600),
                            notes: nil, taskID: taskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .ok)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 2)
            }
        }

        @Test("overlap rejection is global across containers, not scoped to one")
        func rejectsOverlapAcrossDifferentContainers() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let project = try await makeProject(app)
                let existingStart = Date(timeIntervalSince1970: 1_800_000_000)
                let existingEnd = existingStart.addingTimeInterval(3600)
                try await TimeEntry(
                    startDate: existingStart, endDate: existingEnd, container: .task(try task.requireID())
                ).save(on: app.db)

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: existingStart.addingTimeInterval(600),
                            endDate: existingEnd.addingTimeInterval(600),
                            notes: nil, taskID: nil, projectID: try project.requireID(), clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("creating a manual Time Entry that overlaps a running timer is rejected")
        func rejectsOverlapWithARunningTimer() async throws {
            try await withTimeEntriesApp { app in
                let timerTask = try await makeTask(app, title: "Timer")
                let manualProject = try await makeProject(app)
                // A running timer has no endDate yet — it's still treated
                // as open-ended for overlap purposes (ticket #28), not
                // silently excluded by SQL `NULL > x` semantics.
                try await TimeEntry(
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    container: .task(try timerTask.requireID())
                ).save(on: app.db)

                try await app.testing().test(
                    .POST, "/v1/time-entries",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: Date(timeIntervalSince1970: 1_800_001_000),
                            endDate: Date(timeIntervalSince1970: 1_800_002_000),
                            notes: nil, taskID: nil, projectID: try manualProject.requireID(),
                            clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 1)
            }
        }

        @Test("lists all Time Entries")
        func listsAllTimeEntries() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let project = try await makeProject(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                try await TimeEntry(
                    startDate: start, endDate: start.addingTimeInterval(3600), container: .task(try task.requireID())
                ).save(on: app.db)
                try await TimeEntry(
                    startDate: start.addingTimeInterval(7200), endDate: start.addingTimeInterval(10800),
                    container: .project(try project.requireID())
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/time-entries",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TimeEntryResponse].self)
                        #expect(body.count == 2)
                    }
                )
            }
        }

        @Test("lists Time Entries scoped by taskID, projectID, clientID, and courseID")
        func listsScopedTimeEntries() async throws {
            try await withTimeEntriesApp { app in
                let taskA = try await makeTask(app, title: "A")
                let taskB = try await makeTask(app, title: "B")
                let project = try await makeProject(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                try await TimeEntry(
                    startDate: start, endDate: start.addingTimeInterval(3600), container: .task(try taskA.requireID())
                ).save(on: app.db)
                try await TimeEntry(
                    startDate: start.addingTimeInterval(7200), endDate: start.addingTimeInterval(10800),
                    container: .task(try taskB.requireID())
                ).save(on: app.db)
                try await TimeEntry(
                    startDate: start.addingTimeInterval(14400), endDate: start.addingTimeInterval(18000),
                    container: .project(try project.requireID())
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/time-entries?taskID=\(try taskA.requireID())",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TimeEntryResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.taskID == taskA.id)
                    }
                )

                try await app.testing().test(
                    .GET, "/v1/time-entries?projectID=\(try project.requireID())",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TimeEntryResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.projectID == project.id)
                    }
                )

                // Filters are combinable (AND-ed) — since a Time Entry
                // attaches to exactly one container (ADR-0004), combining
                // filters across different container kinds always yields an
                // empty result rather than a special case.
                try await app.testing().test(
                    .GET, "/v1/time-entries?taskID=\(try taskA.requireID())&projectID=\(try project.requireID())",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TimeEntryResponse].self)
                        #expect(body.isEmpty)
                    }
                )
            }
        }

        @Test("edits a Time Entry's times, notes, and container")
        func editsATimeEntry() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let project = try await makeProject(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let entry = TimeEntry(
                    startDate: start, endDate: start.addingTimeInterval(3600), notes: "Original",
                    container: .task(try task.requireID())
                )
                try await entry.save(on: app.db)
                let id = try entry.requireID()

                let newStart = start.addingTimeInterval(100_000)
                try await app.testing().test(
                    .PUT, "/v1/time-entries/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: newStart, endDate: newStart.addingTimeInterval(1800), notes: "Updated",
                            taskID: nil, projectID: try project.requireID(), clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse.self)
                        #expect(body.startDate == newStart)
                        #expect(body.notes == "Updated")
                        #expect(body.taskID == nil)
                        #expect(body.projectID == project.id)
                    }
                )

                let stored = try await TimeEntry.find(id, on: app.db)
                #expect(stored?.notes == "Updated")
                #expect(stored?.container == .project(try project.requireID()))
            }
        }

        @Test("editing a Time Entry without changing its span doesn't overlap itself")
        func editingWithoutChangingSpanSucceeds() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let entry = TimeEntry(
                    startDate: start, endDate: start.addingTimeInterval(3600), notes: nil,
                    container: .task(try task.requireID())
                )
                try await entry.save(on: app.db)
                let id = try entry.requireID()

                try await app.testing().test(
                    .PUT, "/v1/time-entries/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start.addingTimeInterval(3600), notes: "Now with notes",
                            taskID: try task.requireID(), projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                    }
                )
            }
        }

        @Test("editing a Time Entry to overlap a different existing one fails")
        func editingToOverlapAnotherFails() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let taskID = try task.requireID()
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                try await TimeEntry(
                    startDate: start, endDate: start.addingTimeInterval(3600), container: .task(taskID)
                ).save(on: app.db)
                let movable = TimeEntry(
                    startDate: start.addingTimeInterval(7200), endDate: start.addingTimeInterval(10800),
                    container: .task(taskID)
                )
                try await movable.save(on: app.db)
                let id = try movable.requireID()

                try await app.testing().test(
                    .PUT, "/v1/time-entries/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start.addingTimeInterval(1800), endDate: start.addingTimeInterval(5400),
                            notes: nil, taskID: taskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("editing a Time Entry that doesn't exist 404s")
        func editingMissingTimeEntryFails() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .PUT, "/v1/time-entries/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveTimeEntryRequest(
                            startDate: start, endDate: start.addingTimeInterval(3600), notes: nil,
                            taskID: try task.requireID(), projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("rejects a malformed Time Entry id")
        func rejectsMalformedTimeEntryID() async throws {
            try await withTimeEntriesApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/time-entries/not-a-uuid",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("deletes a Time Entry")
        func deletesATimeEntry() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let entry = TimeEntry(
                    startDate: start, endDate: start.addingTimeInterval(3600),
                    container: .task(try task.requireID())
                )
                try await entry.save(on: app.db)
                let id = try entry.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/time-entries/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await TimeEntry.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting a Time Entry that doesn't exist 404s")
        func deletingMissingTimeEntryFails() async throws {
            try await withTimeEntriesApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/time-entries/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        // Ticket #29: deleting a Task/Project/Client/Course while a Time
        // Entry still references it is now rejected, not cascaded — see
        // `TaskTests`/`ProjectTests`/`ClientTests`/`CourseTests` for that
        // coverage, same seam as this suite's own CRUD tests.

        // MARK: - Live Timer (ticket #28)

        @Test("starts a timer with startDate=now and no endDate yet")
        func startsATimer() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let taskID = try task.requireID()
                let before = Date()

                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: taskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse.self)
                        #expect(body.taskID == taskID)
                        #expect(body.endDate == nil)
                    }
                )

                // Compared against the stored model, not the decoded HTTP
                // response: the response round-trips through Vapor's
                // default (whole-second) ISO 8601 JSON encoding, which
                // would make a sub-second `>=` comparison flaky.
                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.isRunning == true)
                #expect((stored.first?.startDate ?? .distantPast) >= before)
            }
        }

        @Test(
            "rejects starting a timer with a bad container",
            arguments: [
                // (taskID given?, projectID given?) — zero containers, then
                // more than one — mirrors `create`'s own container checks.
                (false, false),
                (true, true),
            ]
        )
        func rejectsStartingTimerWithBadContainer(giveTaskID: Bool, giveProjectID: Bool) async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let project = try await makeProject(app)

                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: giveTaskID ? try task.requireID() : nil,
                            projectID: giveProjectID ? try project.requireID() : nil,
                            clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects starting a timer against a Task that doesn't exist")
        func rejectsStartingTimerWithNonexistentContainer() async throws {
            try await withTimeEntriesApp { app in
                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: UUID(), projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("rejects starting a timer while one is already running")
        func rejectsStartingASecondTimer() async throws {
            try await withTimeEntriesApp { app in
                let taskA = try await makeTask(app, title: "A")
                let taskB = try await makeTask(app, title: "B")

                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: try taskA.requireID(), projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .ok)
                    }
                )

                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: try taskB.requireID(), projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.$task.id == (try taskA.requireID()))
            }
        }

        @Test("GET timer returns null when none is running")
        func getTimerReturnsNullWhenNoneRunning() async throws {
            try await withTimeEntriesApp { app in
                try await app.testing().test(
                    .GET, "/v1/time-entries/timer",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse?.self)
                        #expect(body == nil)
                    }
                )
            }
        }

        @Test("GET timer reflects a timer started by a separate request — server-side state")
        func getTimerReflectsSeparatelyStartedTimer() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let taskID = try task.requireID()

                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: taskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .ok)
                    }
                )

                // A separate, unrelated request — proving the running timer
                // is server-side state, not scoped to the request that
                // started it.
                try await app.testing().test(
                    .GET, "/v1/time-entries/timer",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse?.self)
                        #expect(body?.taskID == taskID)
                        #expect(body?.endDate == nil)
                    }
                )
            }
        }

        @Test("stops a running timer into a completed Time Entry")
        func stopsATimer() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let taskID = try task.requireID()
                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: taskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/time-entries/timer/stop",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TimeEntryResponse.self)
                        #expect(body.taskID == taskID)
                        #expect(body.endDate != nil)
                    }
                )

                // Compared against the stored model, not the decoded HTTP
                // response — see `startsATimer`'s comment on why.
                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.isRunning == false)
                #expect((stored.first?.endDate ?? .distantPast) > stored.first!.startDate)

                // No longer the active timer.
                try await app.testing().test(
                    .GET, "/v1/time-entries/timer",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let body = try res.content.decode(TimeEntryResponse?.self)
                        #expect(body == nil)
                    }
                )
            }
        }

        @Test("stopping a timer whose resulting span wouldn't be after its start is rejected and leaves it running")
        func stoppingNonPositiveDurationTimerFailsAndLeavesItRunning() async throws {
            try await withTimeEntriesApp { app in
                // A `startDate` far in the future relative to real "now" —
                // deterministically forces `stopTimer`'s
                // `endDate (= Date()) > startDate` check to fail, the same
                // validator `create`/`update` share (`rejectsNonPositiveDuration`),
                // without this test needing to control the server's clock.
                let task = try await makeTask(app)
                let taskID = try task.requireID()
                try await TimeEntry(
                    startDate: Date().addingTimeInterval(1_000_000), container: .task(taskID)
                ).save(on: app.db)

                try await app.testing().test(
                    .PUT, "/v1/time-entries/timer/stop",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.isRunning == true)
            }
        }

        @Test("stopping a timer that would overlap an existing entry is rejected and leaves it running")
        func stoppingOverlappingTimerFailsAndLeavesItRunning() async throws {
            try await withTimeEntriesApp { app in
                // Spans from well before to well after "now", however long
                // this test takes to run — guaranteed to overlap whatever
                // `stopTimer`'s `Date()` actually resolves to, without this
                // test needing to control the server's clock.
                let existingTask = try await makeTask(app, title: "Existing")
                try await TimeEntry(
                    startDate: Date(timeIntervalSince1970: 0),
                    endDate: Date().addingTimeInterval(86400),
                    container: .task(try existingTask.requireID())
                ).save(on: app.db)

                let timerTask = try await makeTask(app, title: "Timer")
                let timerTaskID = try timerTask.requireID()
                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: timerTaskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/time-entries/timer/stop",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                // Left running, unchanged.
                var runningQuery = TimeEntry.query(on: app.db)
                runningQuery = runningQuery.filter(\.$task.$id == timerTaskID)
                let running = try await runningQuery.first()
                #expect(running?.isRunning == true)

                try await app.testing().test(
                    .GET, "/v1/time-entries/timer",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let body = try res.content.decode(TimeEntryResponse?.self)
                        #expect(body?.taskID == timerTaskID)
                    }
                )
            }
        }

        @Test("stopping a timer that isn't running 404s")
        func stoppingMissingTimerFails() async throws {
            try await withTimeEntriesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/time-entries/timer/stop",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("cancels a running timer, deleting it with no saved record")
        func cancelsATimer() async throws {
            try await withTimeEntriesApp { app in
                let task = try await makeTask(app)
                let taskID = try task.requireID()
                try await app.testing().test(
                    .POST, "/v1/time-entries/timer/start",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(StartTimerRequest(
                            taskID: taskID, projectID: nil, clientID: nil, courseID: nil
                        ))
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/time-entries/timer/cancel",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await TimeEntry.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("canceling a timer that isn't running 404s")
        func cancelingMissingTimerFails() async throws {
            try await withTimeEntriesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/time-entries/timer/cancel",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }
    }
}
