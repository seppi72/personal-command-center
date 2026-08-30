import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `ProjectTests`/`TaskTests`/`DeadlineTests`: real HTTP
/// requests against a running Vapor app, backed by a real (test) Postgres
/// database. The one exception, per spec #1's testing decision, is the
/// outbound CalDAV call itself — `FakeCalDAVClient` stands in for a live
/// iCloud account.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Personal Commitments", .serialized)
    struct PersonalCommitmentTests {
        @discardableResult
        private func withCommitmentsApp<T>(
            caldav: FakeCalDAVClient = FakeCalDAVClient(),
            _ test: (Application, FakeCalDAVClient) async throws -> T
        ) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                app.calDAVClient = caldav
                try await configure(app)
            }) { app in
                let result = try await test(app, caldav)
                try await AutomationLog.query(on: app.db).delete()
                try await PersonalCommitment.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        private func logs(on app: Application, subjectID: UUID) async throws -> [AutomationLog] {
            try await AutomationLog.query(on: app.db).all().filter { $0.subjectID == subjectID }
        }

        @Test("rejects requests without a bearer token")
        func commitmentsWithoutTokenAreRejected() async throws {
            try await withCommitmentsApp { app, _ in
                try await app.testing().test(.GET, "/v1/personal-commitments", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Personal Commitment and pushes it to CalDAV")
        func createsACommitment() async throws {
            try await withCommitmentsApp { app, caldav in
                let start = Date(timeIntervalSince1970: 1_800_000_000)
                let end = Date(timeIntervalSince1970: 1_800_003_600)

                try await app.testing().test(
                    .POST, "/v1/personal-commitments",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Dentist",
                            startDate: start,
                            endDate: end,
                            recurrenceRule: nil,
                            courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(PersonalCommitmentResponse.self)
                        #expect(body.title == "Dentist")
                        #expect(body.startDate == start)
                        #expect(body.endDate == end)
                        #expect(body.syncStatus == "synced")
                    }
                )

                let stored = try await PersonalCommitment.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.syncStatus == .synced)

                let calls = await caldav.calls
                #expect(calls.count == 1)
                if case let .upsert(event) = calls.first {
                    #expect(event.title == "Dentist")
                    #expect(event.uid == stored.first?.externalEventID)
                } else {
                    Issue.record("expected an upsert call")
                }

                let entries = try await logs(on: app, subjectID: try stored.first!.requireID())
                #expect(entries.count == 1)
                #expect(entries.first?.actionType == "personal_commitment.create")
                #expect(entries.first?.outcome == .success)
            }
        }

        @Test("creates a Commitment with a Course link and round-trips it")
        func createsACommitmentWithACourse() async throws {
            try await withCommitmentsApp { app, _ in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let courseID = try course.requireID()
                let start = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .POST, "/v1/personal-commitments",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "CS 301 Lecture",
                            startDate: start,
                            endDate: start.addingTimeInterval(3600),
                            recurrenceRule: "FREQ=WEEKLY",
                            courseID: courseID
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(PersonalCommitmentResponse.self)
                        #expect(body.courseID == courseID)
                    }
                )

                let stored = try await PersonalCommitment.query(on: app.db).all()
                #expect(stored.first?.$course.id == courseID)

                try await Course.query(on: app.db).delete()
            }
        }

        @Test("rejects creating a Commitment with a Course ID that doesn't exist")
        func rejectsNonexistentCourseOnCreate() async throws {
            try await withCommitmentsApp { app, _ in
                try await app.testing().test(
                    .POST, "/v1/personal-commitments",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Orphaned",
                            startDate: Date(),
                            endDate: Date().addingTimeInterval(3600),
                            recurrenceRule: nil,
                            courseID: UUID()
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await PersonalCommitment.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects creating a Commitment with an empty or whitespace-only title")
        func rejectsEmptyCommitmentTitle() async throws {
            try await withCommitmentsApp { app, _ in
                try await app.testing().test(
                    .POST, "/v1/personal-commitments",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "   ",
                            startDate: Date(),
                            endDate: Date().addingTimeInterval(3600),
                            recurrenceRule: nil,
                            courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await PersonalCommitment.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects creating a Commitment whose end time isn't after its start time")
        func rejectsNonPositiveDuration() async throws {
            try await withCommitmentsApp { app, _ in
                let sameInstant = Date(timeIntervalSince1970: 1_800_000_000)
                try await app.testing().test(
                    .POST, "/v1/personal-commitments",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Backwards",
                            startDate: sameInstant,
                            endDate: sameInstant,
                            recurrenceRule: nil,
                            courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("edits a Commitment and re-pushes it to CalDAV under the same UID")
        func editsACommitment() async throws {
            try await withCommitmentsApp { app, caldav in
                let commitment = PersonalCommitment(
                    title: "Original",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600)
                )
                try await commitment.save(on: app.db)
                let id = try commitment.requireID()
                let originalUID = commitment.externalEventID
                let newStart = Date(timeIntervalSince1970: 1_900_000_000)
                let newEnd = Date(timeIntervalSince1970: 1_900_003_600)

                try await app.testing().test(
                    .PUT, "/v1/personal-commitments/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Renamed",
                            startDate: newStart,
                            endDate: newEnd,
                            recurrenceRule: "FREQ=WEEKLY",
                            courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(PersonalCommitmentResponse.self)
                        #expect(body.title == "Renamed")
                        #expect(body.recurrenceRule == "FREQ=WEEKLY")
                        #expect(body.syncStatus == "synced")
                    }
                )

                let stored = try await PersonalCommitment.find(id, on: app.db)
                #expect(stored?.title == "Renamed")
                #expect(stored?.externalEventID == originalUID)

                let calls = await caldav.calls
                #expect(calls.count == 1)
                if case let .upsert(event) = calls.first {
                    #expect(event.uid == originalUID)
                    #expect(event.title == "Renamed")
                } else {
                    Issue.record("expected an upsert call")
                }
            }
        }

        @Test("attaches a Course to a Commitment on edit, then clears it back to none")
        func editsACommitmentsCourse() async throws {
            try await withCommitmentsApp { app, _ in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let courseID = try course.requireID()

                let commitment = PersonalCommitment(
                    title: "Lecture",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600)
                )
                try await commitment.save(on: app.db)
                let id = try commitment.requireID()

                try await app.testing().test(
                    .PUT, "/v1/personal-commitments/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Lecture",
                            startDate: commitment.startDate,
                            endDate: commitment.endDate,
                            recurrenceRule: nil,
                            courseID: courseID
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(PersonalCommitmentResponse.self)
                        #expect(body.courseID == courseID)
                    }
                )

                try await app.testing().test(
                    .PUT, "/v1/personal-commitments/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Lecture",
                            startDate: commitment.startDate,
                            endDate: commitment.endDate,
                            recurrenceRule: nil,
                            courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(PersonalCommitmentResponse.self)
                        #expect(body.courseID == nil)
                    }
                )

                try await Course.query(on: app.db).delete()
            }
        }

        @Test("rejects editing a Commitment with a Course ID that doesn't exist")
        func rejectsNonexistentCourseOnEdit() async throws {
            try await withCommitmentsApp { app, _ in
                let commitment = PersonalCommitment(
                    title: "Lecture",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600)
                )
                try await commitment.save(on: app.db)
                let id = try commitment.requireID()

                try await app.testing().test(
                    .PUT, "/v1/personal-commitments/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Lecture",
                            startDate: commitment.startDate,
                            endDate: commitment.endDate,
                            recurrenceRule: nil,
                            courseID: UUID()
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await PersonalCommitment.find(id, on: app.db)
                #expect(stored?.$course.id == nil)
            }
        }

        @Test("editing a Commitment that doesn't exist 404s")
        func editingMissingCommitmentFails() async throws {
            try await withCommitmentsApp { app, _ in
                try await app.testing().test(
                    .PUT, "/v1/personal-commitments/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Doesn't matter",
                            startDate: Date(),
                            endDate: Date().addingTimeInterval(3600),
                            recurrenceRule: nil,
                            courseID: nil
                        ))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Commitment and removes its CalDAV event")
        func deletesACommitment() async throws {
            try await withCommitmentsApp { app, caldav in
                let commitment = PersonalCommitment(
                    title: "Throwaway",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600)
                )
                try await commitment.save(on: app.db)
                let id = try commitment.requireID()
                let uid = commitment.externalEventID

                try await app.testing().test(
                    .DELETE, "/v1/personal-commitments/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PersonalCommitment.find(id, on: app.db)
                #expect(stored == nil)

                let calls = await caldav.calls
                #expect(calls == [.delete(uid: uid)])

                let entries = try await logs(on: app, subjectID: id)
                #expect(entries.count == 1)
                #expect(entries.first?.actionType == "personal_commitment.delete")
                #expect(entries.first?.outcome == .success)
            }
        }

        @Test("deletes a Commitment with a Course link the same as one without")
        func deletesACommitmentWithACourse() async throws {
            try await withCommitmentsApp { app, _ in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let courseID = try course.requireID()

                let commitment = PersonalCommitment(
                    title: "Lecture",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600),
                    courseID: courseID
                )
                try await commitment.save(on: app.db)
                let id = try commitment.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/personal-commitments/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PersonalCommitment.find(id, on: app.db)
                #expect(stored == nil)

                // The Course itself is untouched — only the Commitment
                // side of the link is deleted.
                let storedCourse = try await Course.find(courseID, on: app.db)
                #expect(storedCourse != nil)

                try await Course.query(on: app.db).delete()
            }
        }

        @Test(
            "a CalDAV delete failure still removes the Commitment locally and logs the failure"
        )
        func caldavDeleteFailureIsLoggedNotFatal() async throws {
            let caldav = FakeCalDAVClient(failureToThrow: CalDAVClientError.serverError(status: 503))
            try await withCommitmentsApp(caldav: caldav) { app, caldav in
                let commitment = PersonalCommitment(
                    title: "Won't delete cleanly",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600)
                )
                try await commitment.save(on: app.db)
                let id = try commitment.requireID()
                let uid = commitment.externalEventID

                try await app.testing().test(
                    .DELETE, "/v1/personal-commitments/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        // The local, canonical row is still removed even
                        // though the CalDAV delete failed — the failure is
                        // a logged state (spec #1's "clear error state"
                        // requirement), not a reason to keep a Commitment
                        // around that the owner already asked to delete.
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PersonalCommitment.find(id, on: app.db)
                #expect(stored == nil)

                let calls = await caldav.calls
                #expect(calls == [.delete(uid: uid)])

                let entries = try await logs(on: app, subjectID: id)
                #expect(entries.count == 1)
                #expect(entries.first?.actionType == "personal_commitment.delete")
                #expect(entries.first?.outcome == .failure)
                #expect(entries.first?.detail.contains("CalDAV delete failed") == true)
            }
        }

        @Test("deleting a Commitment that doesn't exist 404s")
        func deletingMissingCommitmentFails() async throws {
            try await withCommitmentsApp { app, _ in
                try await app.testing().test(
                    .DELETE, "/v1/personal-commitments/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("lists all Personal Commitments")
        func listsAllCommitments() async throws {
            try await withCommitmentsApp { app, _ in
                try await PersonalCommitment(
                    title: "First",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600)
                ).save(on: app.db)
                try await PersonalCommitment(
                    title: "Second",
                    startDate: Date(timeIntervalSince1970: 1_900_000_000),
                    endDate: Date(timeIntervalSince1970: 1_900_003_600)
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/personal-commitments",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([PersonalCommitmentResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.title)) == ["First", "Second"])
                    }
                )
            }
        }

        @Test("filters Personal Commitments by ?courseID=")
        func filtersCommitmentsByCourse() async throws {
            try await withCommitmentsApp { app, _ in
                let course = Course(name: "CS 301", termMonth: 9, termYear: 2026)
                try await course.save(on: app.db)
                let courseID = try course.requireID()

                try await PersonalCommitment(
                    title: "CS 301 Lecture",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600),
                    courseID: courseID
                ).save(on: app.db)
                try await PersonalCommitment(
                    title: "Dentist",
                    startDate: Date(timeIntervalSince1970: 1_900_000_000),
                    endDate: Date(timeIntervalSince1970: 1_900_003_600)
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/personal-commitments?courseID=\(courseID)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([PersonalCommitmentResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.title == "CS 301 Lecture")
                    }
                )

                try await Course.query(on: app.db).delete()
            }
        }

        @Test(
            "a CalDAV push failure still saves the Commitment locally, marks it failed, and logs the failure"
        )
        func caldavFailureIsLoggedNotFatal() async throws {
            let caldav = FakeCalDAVClient(failureToThrow: CalDAVClientError.serverError(status: 503))
            try await withCommitmentsApp(caldav: caldav) { app, caldav in
                try await app.testing().test(
                    .POST, "/v1/personal-commitments",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SavePersonalCommitmentRequest(
                            title: "Will fail to sync",
                            startDate: Date(timeIntervalSince1970: 1_800_000_000),
                            endDate: Date(timeIntervalSince1970: 1_800_003_600),
                            recurrenceRule: nil,
                            courseID: nil
                        ))
                    },
                    afterResponse: { res async throws in
                        // The canonical write still succeeds — a sync
                        // failure is a visible, logged state, not an API
                        // error (spec #1's "clear error state" requirement).
                        #expect(res.status == .ok)
                        let body = try res.content.decode(PersonalCommitmentResponse.self)
                        #expect(body.syncStatus == "failed")
                    }
                )

                let stored = try await PersonalCommitment.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.syncStatus == .failed)

                let entries = try await logs(on: app, subjectID: try stored.first!.requireID())
                #expect(entries.count == 1)
                #expect(entries.first?.outcome == .failure)
                #expect(entries.first?.detail.contains("CalDAV push failed") == true)
            }
        }
    }
}
