import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `AccountTests`/`TimeEntryTests`: real HTTP requests against a
/// running Vapor app, backed by a real (test) Postgres database. Shares the
/// `accounts` table with `AccountTests` and the `categories`/`subcategories`
/// tables with `CategoryTests`/`SubcategoryTests`, so all of them clean up on
/// teardown.
extension AppTestSuite {
    @Suite("Transactions", .serialized)
    struct TransactionTests {
        @discardableResult
        private func withTransactionsApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await Transaction.query(on: app.db).delete()
                try await Account.query(on: app.db).delete()
                try await Subcategory.query(on: app.db).delete()
                try await PCCCategory.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        private func makeAccount(_ app: Application, name: String = "Checking", openingBalance: Double = 0) async throws -> Account {
            let account = Account(name: name, type: .checking, openingBalance: openingBalance)
            try await account.save(on: app.db)
            return account
        }

        private func makeCategory(_ app: Application, name: String = "Food") async throws -> PCCCategory {
            let category = PCCCategory(name: name)
            try await category.save(on: app.db)
            return category
        }

        @Test("rejects requests without a bearer token")
        func transactionsWithoutTokenAreRejected() async throws {
            try await withTransactionsApp { app in
                try await app.testing().test(.GET, "/v1/transactions", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Transaction against an Account")
        func createsATransaction() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let accountID = try account.requireID()
                let date = Date(timeIntervalSince1970: 1_800_000_000)

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: accountID, amount: 42.50, type: .expense, date: date, notes: "Groceries", categoryID: nil, subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TransactionResponse.self)
                        #expect(body.accountID == accountID)
                        #expect(body.amount == 42.50)
                        #expect(body.type == .expense)
                        #expect(body.notes == "Groceries")
                    }
                )

                let stored = try await Transaction.query(on: app.db).all()
                #expect(stored.count == 1)
            }
        }

        @Test("rejects creating a Transaction against an Account that doesn't exist")
        func rejectsNonexistentAccount() async throws {
            try await withTransactionsApp { app in
                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: UUID(), amount: 10, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil, categoryID: nil, subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Transaction.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test(
            "rejects creating a Transaction with a zero or negative amount",
            arguments: [0.0, -5.0]
        )
        func rejectsNonPositiveAmount(amount: Double) async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: amount, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil, categoryID: nil, subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Transaction.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        private struct MalformedTransactionPayload: Content {
            let accountID: UUID
            let amount: Double
            let type: String
            let date: Date
            let notes: String?
        }

        @Test("rejects creating a Transaction with an unrecognized type")
        func rejectsUnrecognizedType() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            MalformedTransactionPayload(
                                accountID: try account.requireID(), amount: 10, type: "refund",
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("does not reject two Transactions logged on the same date")
        func allowsSameDateTransactions() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let accountID = try account.requireID()
                let date = Date(timeIntervalSince1970: 1_800_000_000)

                for _ in 0..<2 {
                    try await app.testing().test(
                        .POST, "/v1/transactions",
                        headers: authHeaders(),
                        beforeRequest: { req async throws in
                            try req.content.encode(
                                SaveTransactionRequest(
                                    accountID: accountID, amount: 5, type: .expense, date: date, notes: nil, categoryID: nil, subcategoryID: nil
                                )
                            )
                        },
                        afterResponse: { res async in
                            #expect(res.status == .ok)
                        }
                    )
                }

                let stored = try await Transaction.query(on: app.db).all()
                #expect(stored.count == 2)
            }
        }

        @Test("lists all Transactions")
        func listsAllTransactions() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let accountID = try account.requireID()
                try await Transaction(
                    amount: 20, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000), accountID: accountID
                ).save(on: app.db)
                try await Transaction(
                    amount: 100, type: .income, date: Date(timeIntervalSince1970: 1_800_003_600), accountID: accountID
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/transactions",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TransactionResponse].self)
                        #expect(body.count == 2)
                    }
                )
            }
        }

        @Test("filters Transactions by Account")
        func filtersByAccount() async throws {
            try await withTransactionsApp { app in
                let matching = try await makeAccount(app, name: "Checking")
                let other = try await makeAccount(app, name: "Savings")
                try await Transaction(
                    amount: 20, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000),
                    accountID: try matching.requireID()
                ).save(on: app.db)
                try await Transaction(
                    amount: 30, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000),
                    accountID: try other.requireID()
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/transactions?accountID=\(try matching.requireID())",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TransactionResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.accountID == matching.id)
                    }
                )
            }
        }

        @Test("filters Transactions by a [start, end) date range")
        func filtersByDateRange() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let accountID = try account.requireID()
                let inRange = Date(timeIntervalSince1970: 1_800_003_600)
                let beforeRange = Date(timeIntervalSince1970: 1_800_000_000)
                let afterRange = Date(timeIntervalSince1970: 1_800_100_000)
                try await Transaction(amount: 1, type: .expense, date: beforeRange, accountID: accountID).save(on: app.db)
                try await Transaction(amount: 2, type: .expense, date: inRange, accountID: accountID).save(on: app.db)
                try await Transaction(amount: 3, type: .expense, date: afterRange, accountID: accountID).save(on: app.db)

                let formatter = ISO8601DateFormatter()
                let start = formatter.string(from: Date(timeIntervalSince1970: 1_800_003_000))
                let end = formatter.string(from: Date(timeIntervalSince1970: 1_800_010_000))

                try await app.testing().test(
                    .GET, "/v1/transactions?start=\(start)&end=\(end)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([TransactionResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.amount == 2)
                    }
                )
            }
        }

        @Test("rejects a malformed Transaction id")
        func rejectsMalformedTransactionID() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)

                try await app.testing().test(
                    .PUT, "/v1/transactions/not-a-uuid",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: 5, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil, categoryID: nil, subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("edits a Transaction")
        func editsATransaction() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let accountID = try account.requireID()
                let transaction = Transaction(
                    amount: 20, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000), accountID: accountID
                )
                try await transaction.save(on: app.db)
                let id = try transaction.requireID()
                let newDate = Date(timeIntervalSince1970: 1_800_003_600)

                try await app.testing().test(
                    .PUT, "/v1/transactions/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: accountID, amount: 99, type: .income, date: newDate, notes: "Refund", categoryID: nil, subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TransactionResponse.self)
                        #expect(body.amount == 99)
                        #expect(body.type == .income)
                        #expect(body.notes == "Refund")
                    }
                )

                let stored = try await Transaction.find(id, on: app.db)
                #expect(stored?.amount == 99)
                #expect(stored?.type == .income)
            }
        }

        @Test("editing a Transaction that doesn't exist 404s")
        func editingMissingTransactionFails() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)

                try await app.testing().test(
                    .PUT, "/v1/transactions/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: 5, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil, categoryID: nil, subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Transaction")
        func deletesATransaction() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let transaction = Transaction(
                    amount: 20, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000),
                    accountID: try account.requireID()
                )
                try await transaction.save(on: app.db)
                let id = try transaction.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/transactions/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Transaction.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting a Transaction that doesn't exist 404s")
        func deletingMissingTransactionFails() async throws {
            try await withTransactionsApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/transactions/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("tags a Transaction with a Category alone")
        func tagsTransactionWithCategoryAlone() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let category = try await makeCategory(app)
                let categoryID = try category.requireID()

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: 10, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil,
                                categoryID: categoryID, subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TransactionResponse.self)
                        #expect(body.categoryID == categoryID)
                        #expect(body.subcategoryID == nil)
                    }
                )
            }
        }

        @Test("tags a Transaction with a Category and its Subcategory")
        func tagsTransactionWithCategoryAndSubcategory() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let category = try await makeCategory(app)
                let categoryID = try category.requireID()
                let subcategory = Subcategory(name: "Groceries", categoryID: categoryID)
                try await subcategory.save(on: app.db)
                let subcategoryID = try subcategory.requireID()

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: 10, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil,
                                categoryID: categoryID, subcategoryID: subcategoryID
                            )
                        )
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TransactionResponse.self)
                        #expect(body.categoryID == categoryID)
                        #expect(body.subcategoryID == subcategoryID)
                    }
                )
            }
        }

        @Test("rejects tagging a Transaction with a subcategoryID but no categoryID")
        func rejectsSubcategoryWithoutCategory() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let category = try await makeCategory(app)
                let subcategory = Subcategory(name: "Groceries", categoryID: try category.requireID())
                try await subcategory.save(on: app.db)

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: 10, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil,
                                categoryID: nil, subcategoryID: try subcategory.requireID()
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Transaction.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects tagging a Transaction with a subcategoryID that belongs to a different categoryID")
        func rejectsSubcategoryFromOtherCategory() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let categoryA = try await makeCategory(app, name: "Food")
                let categoryB = try await makeCategory(app, name: "Transport")
                let subcategoryOfA = Subcategory(name: "Groceries", categoryID: try categoryA.requireID())
                try await subcategoryOfA.save(on: app.db)

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: 10, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil,
                                categoryID: try categoryB.requireID(), subcategoryID: try subcategoryOfA.requireID()
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Transaction.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects a nonexistent categoryID")
        func rejectsNonexistentCategory() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: 10, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil,
                                categoryID: UUID(), subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("rejects a nonexistent subcategoryID")
        func rejectsNonexistentSubcategory() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let category = try await makeCategory(app)

                try await app.testing().test(
                    .POST, "/v1/transactions",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: try account.requireID(), amount: 10, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil,
                                categoryID: try category.requireID(), subcategoryID: UUID()
                            )
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("edits a Transaction to remove its Category/Subcategory tagging")
        func editsTransactionToClearTagging() async throws {
            try await withTransactionsApp { app in
                let account = try await makeAccount(app)
                let accountID = try account.requireID()
                let category = try await makeCategory(app)
                let categoryID = try category.requireID()
                let subcategory = Subcategory(name: "Groceries", categoryID: categoryID)
                try await subcategory.save(on: app.db)
                let transaction = Transaction(
                    amount: 20, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000),
                    accountID: accountID, categoryID: categoryID, subcategoryID: try subcategory.requireID()
                )
                try await transaction.save(on: app.db)
                let id = try transaction.requireID()

                try await app.testing().test(
                    .PUT, "/v1/transactions/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            SaveTransactionRequest(
                                accountID: accountID, amount: 20, type: .expense,
                                date: Date(timeIntervalSince1970: 1_800_000_000), notes: nil,
                                categoryID: nil, subcategoryID: nil
                            )
                        )
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(TransactionResponse.self)
                        #expect(body.categoryID == nil)
                        #expect(body.subcategoryID == nil)
                    }
                )

                let stored = try await Transaction.find(id, on: app.db)
                #expect(stored?.$category.id == nil)
                #expect(stored?.$subcategory.id == nil)
            }
        }
    }
}
