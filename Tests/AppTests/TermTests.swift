import Fluent
import Testing
import VaporTesting

@testable import App

/// Same seam as `CourseTests`: real HTTP requests against a running Vapor
/// app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Terms", .serialized)
    struct TermTests {
        @discardableResult
        private func withTermsApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                // Courses first: a Term can't be deleted while one still
                // references it, which is the guard these tests exercise.
                try await Course.query(on: app.db).delete()
                try await Term.query(on: app.db).delete()
                let result = try await test(app)
                try await Course.query(on: app.db).delete()
                try await Term.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        private func save(
            _ app: Application, year: Int, semester: Semester, startDate: Date? = nil,
            endDate: Date? = nil, headers: HTTPHeaders? = nil,
            expect status: HTTPStatus = .ok
        ) async throws {
            try await app.testing().test(
                .POST, "/v1/terms",
                headers: headers ?? authHeaders(),
                beforeRequest: { req async throws in
                    try req.content.encode(
                        SaveTermRequest(
                            year: year, semester: semester, startDate: startDate, endDate: endDate))
                },
                afterResponse: { res async in
                    #expect(res.status == status)
                }
            )
        }

        private static let augustEleventh = Date(timeIntervalSince1970: 1_754_870_400)
        private static let decemberTwentieth = Date(timeIntervalSince1970: 1_766_188_800)

        @Test("rejects requests without a bearer token")
        func termsWithoutTokenAreRejected() async throws {
            try await withTermsApp { app in
                try await app.testing().test(.GET, "/v1/terms", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Term and derives its display name from year and semester")
        func createsATerm() async throws {
            try await withTermsApp { app in
                try await app.testing().test(
                    .POST, "/v1/terms",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTermRequest(
                                year: 2026, semester: .first, startDate: Self.augustEleventh,
                                endDate: Self.decemberTwentieth))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TermResponse.self)
                        #expect(body.year == 2026)
                        #expect(body.semester == .first)
                        #expect(body.displayName == "1st Semester 2026")
                        #expect(body.startDate == Self.augustEleventh)
                    }
                )
            }
        }

        @Test("a Term's dates are optional")
        func datesAreOptional() async throws {
            try await withTermsApp { app in
                try await save(app, year: 2026, semester: .first)

                let stored = try await Term.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.startDate == nil)
                #expect(stored.first?.endDate == nil)
            }
        }

        /// Half a span can neither be overlap-checked against another Term
        /// nor asked whether it contains today, so it's rejected rather than
        /// stored (`docs/adr/0012-term-is-an-entity.md`).
        @Test("rejects a start date without an end date, and the reverse")
        func rejectsHalfASpan() async throws {
            try await withTermsApp { app in
                try await save(
                    app, year: 2026, semester: .first, startDate: Self.augustEleventh,
                    expect: .badRequest)
                try await save(
                    app, year: 2026, semester: .first, endDate: Self.decemberTwentieth,
                    expect: .badRequest)

                #expect(try await Term.query(on: app.db).all().isEmpty)
            }
        }

        @Test("rejects an end date before the start date")
        func rejectsBackwardsSpan() async throws {
            try await withTermsApp { app in
                try await save(
                    app, year: 2026, semester: .first, startDate: Self.decemberTwentieth,
                    endDate: Self.augustEleventh, expect: .badRequest)

                #expect(try await Term.query(on: app.db).all().isEmpty)
            }
        }

        /// Year plus semester is a Term's identity. A duplicate would split
        /// one semester's Courses across two Terms, halving every per-Term
        /// figure computed over them.
        @Test("rejects a second Term with the same year and semester")
        func rejectsDuplicateYearAndSemester() async throws {
            try await withTermsApp { app in
                try await save(app, year: 2026, semester: .first)
                try await save(app, year: 2026, semester: .first, expect: .badRequest)
                // The same year with a different semester is fine — it's the
                // pair that identifies a Term, not the year alone.
                try await save(app, year: 2026, semester: .second)

                #expect(try await Term.query(on: app.db).all().count == 2)
            }
        }

        /// Two overlapping Terms would give "which semester is happening
        /// now" two answers, and the School screen would show a different
        /// one depending on sort order.
        @Test("rejects a Term whose dates overlap another Term's")
        func rejectsOverlappingSpans() async throws {
            try await withTermsApp { app in
                try await save(
                    app, year: 2026, semester: .first, startDate: Self.augustEleventh,
                    endDate: Self.decemberTwentieth)
                try await save(
                    app, year: 2026, semester: .second,
                    startDate: Self.decemberTwentieth.addingTimeInterval(-86_400),
                    endDate: Self.decemberTwentieth.addingTimeInterval(100 * 86_400),
                    expect: .badRequest)
                // Starting the day after the other ends is not an overlap.
                try await save(
                    app, year: 2026, semester: .second,
                    startDate: Self.decemberTwentieth.addingTimeInterval(86_400),
                    endDate: Self.decemberTwentieth.addingTimeInterval(100 * 86_400))

                #expect(try await Term.query(on: app.db).all().count == 2)
            }
        }

        /// An undated Term makes no claim about any stretch of time, so it
        /// can't clash with one that does.
        @Test("a Term with no dates never counts as overlapping")
        func undatedTermsNeverOverlap() async throws {
            try await withTermsApp { app in
                try await save(app, year: 2026, semester: .first)
                try await save(app, year: 2026, semester: .second)
                try await save(
                    app, year: 2026, semester: .summer, startDate: Self.augustEleventh,
                    endDate: Self.decemberTwentieth)

                #expect(try await Term.query(on: app.db).all().count == 3)
            }
        }

        @Test("lists Terms in calendar order, semesters within a year")
        func listsInCalendarOrder() async throws {
            try await withTermsApp { app in
                try await save(app, year: 2027, semester: .first)
                try await save(app, year: 2026, semester: .summer)
                try await save(app, year: 2026, semester: .first)

                try await app.testing().test(
                    .GET, "/v1/terms",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TermResponse].self)
                        #expect(
                            body.map(\.displayName) == [
                                "1st Semester 2026", "Summer 2026", "1st Semester 2027",
                            ])
                    }
                )
            }
        }

        @Test("edits a Term's semester and dates")
        func editsATerm() async throws {
            try await withTermsApp { app in
                let term = try await makeTerm(on: app.db, year: 2026, semester: .first)
                let id = try term.requireID()

                try await app.testing().test(
                    .PUT, "/v1/terms/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTermRequest(
                                year: 2026, semester: .summer, startDate: Self.augustEleventh,
                                endDate: Self.decemberTwentieth))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TermResponse.self)
                        #expect(body.displayName == "Summer 2026")
                        #expect(body.endDate == Self.decemberTwentieth)
                    }
                )
            }
        }

        /// Editing a Term must not trip over the Term's own row — its
        /// current dates always "overlap" themselves.
        @Test("editing a Term doesn't clash with its own dates")
        func editingDoesNotClashWithItself() async throws {
            try await withTermsApp { app in
                let term = try await makeTerm(
                    on: app.db, year: 2026, semester: .first, startDate: Self.augustEleventh,
                    endDate: Self.decemberTwentieth)
                let id = try term.requireID()

                try await app.testing().test(
                    .PUT, "/v1/terms/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTermRequest(
                                year: 2026, semester: .first, startDate: Self.augustEleventh,
                                endDate: Self.decemberTwentieth))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .ok)
                    }
                )
            }
        }

        @Test("editing a Term that doesn't exist 404s")
        func editingMissingTermFails() async throws {
            try await withTermsApp { app in
                try await app.testing().test(
                    .PUT, "/v1/terms/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTermRequest(
                                year: 2026, semester: .first, startDate: nil, endDate: nil))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Term nothing references")
        func deletesATerm() async throws {
            try await withTermsApp { app in
                let id = try await makeTerm(on: app.db, year: 2026, semester: .first).requireID()

                try await app.testing().test(
                    .DELETE, "/v1/terms/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                #expect(try await Term.find(id, on: app.db) == nil)
            }
        }

        /// Cascading would silently delete a semester of academic history,
        /// so the delete is refused while a Course still belongs to the Term
        /// — the same referential guard `CourseController.delete` applies for
        /// its own references.
        @Test("rejects deleting a Term a Course still belongs to")
        func rejectsDeletingReferencedTerm() async throws {
            try await withTermsApp { app in
                let course = try await makeCourse(name: "CS 301", on: app.db)
                let termID = course.$term.id

                try await app.testing().test(
                    .DELETE, "/v1/terms/\(termID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                #expect(try await Term.find(termID, on: app.db) != nil)
            }
        }

        @Test("deleting a Term that doesn't exist 404s")
        func deletingMissingTermFails() async throws {
            try await withTermsApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/terms/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }
    }
}
