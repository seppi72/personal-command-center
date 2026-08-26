import Testing
import VaporTesting

@testable import App

/// Same seam as `ClientTests`/`ProjectTests`: real HTTP requests against a
/// running Vapor app, backed by a real (test) Postgres database. Owns its
/// own `accounts` table, shared with no other suite — nested under
/// `AppTestSuite` anyway for one consistent top-level ordering, the same
/// call `PersonalCommitmentTests` already makes for a table it doesn't
/// share either.
extension AppTestSuite {
    @Suite("Accounts", .serialized)
    struct AccountTests {
        @discardableResult
        private func withAccountsApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await Transaction.query(on: app.db).delete()
                try await Account.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("rejects requests without a bearer token")
        func accountsWithoutTokenAreRejected() async throws {
            try await withAccountsApp { app in
                try await app.testing().test(.GET, "/v1/accounts", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates an Account with a name, type, and opening balance")
        func createsAnAccount() async throws {
            try await withAccountsApp { app in
                try await app.testing().test(
                    .POST, "/v1/accounts",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            CreateAccountRequest(name: "Checking", type: .checking, openingBalance: 100)
                        )
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(AccountResponse.self)
                        #expect(body.name == "Checking")
                        #expect(body.type == .checking)
                        #expect(body.classification == .asset)
                        #expect(body.openingBalance == 100)
                        #expect(body.balance == 100)
                    }
                )

                let stored = try await Account.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.name == "Checking")
                #expect(stored.first?.type == .checking)
                #expect(stored.first?.openingBalance == 100)
            }
        }

        @Test(
            "classifies each AccountType as an asset or liability",
            arguments: [
                (AccountType.checking, AccountClassification.asset),
                (AccountType.savings, AccountClassification.asset),
                (AccountType.cash, AccountClassification.asset),
                (AccountType.investment, AccountClassification.asset),
                (AccountType.creditCard, AccountClassification.liability),
                (AccountType.loan, AccountClassification.liability),
            ]
        )
        func classifiesEachAccountType(type: AccountType, expected: AccountClassification) async throws {
            try await withAccountsApp { app in
                try await app.testing().test(
                    .POST, "/v1/accounts",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(CreateAccountRequest(name: "Test", type: type, openingBalance: 0))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(AccountResponse.self)
                        #expect(body.classification == expected)
                    }
                )
            }
        }

        @Test("rejects creating an Account with an empty or whitespace-only name")
        func rejectsEmptyAccountName() async throws {
            try await withAccountsApp { app in
                try await app.testing().test(
                    .POST, "/v1/accounts",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            CreateAccountRequest(name: "   ", type: .checking, openingBalance: 0)
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Account.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        private struct MalformedAccountPayload: Content {
            let name: String
            let type: String
            let openingBalance: Double
        }

        @Test("rejects creating an Account with an unrecognized type")
        func rejectsUnrecognizedAccountType() async throws {
            try await withAccountsApp { app in
                try await app.testing().test(
                    .POST, "/v1/accounts",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(
                            MalformedAccountPayload(name: "Mystery", type: "cryptoWallet", openingBalance: 0)
                        )
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("rejects a malformed Account id")
        func rejectsMalformedAccountID() async throws {
            try await withAccountsApp { app in
                try await app.testing().test(
                    .PUT, "/v1/accounts/not-a-uuid",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(UpdateAccountRequest(name: "Doesn't matter", type: .checking))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("lists all Accounts with their Balance")
        func listsAllAccounts() async throws {
            try await withAccountsApp { app in
                try await Account(name: "Checking", type: .checking, openingBalance: 500).save(on: app.db)
                try await Account(name: "Credit Card", type: .creditCard, openingBalance: -200).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/accounts",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([AccountResponse].self)
                        #expect(body.count == 2)
                        let byName = Dictionary(uniqueKeysWithValues: body.map { ($0.name, $0) })
                        #expect(byName["Checking"]?.balance == 500)
                        #expect(byName["Checking"]?.classification == .asset)
                        #expect(byName["Credit Card"]?.balance == -200)
                        #expect(byName["Credit Card"]?.classification == .liability)
                    }
                )
            }
        }

        @Test("edits an Account's name and type, leaving its opening balance untouched")
        func editsAnAccountsNameAndType() async throws {
            try await withAccountsApp { app in
                let account = Account(name: "Original", type: .checking, openingBalance: 250)
                try await account.save(on: app.db)
                let id = try account.requireID()

                try await app.testing().test(
                    .PUT, "/v1/accounts/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(UpdateAccountRequest(name: "Renamed", type: .savings))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(AccountResponse.self)
                        #expect(body.name == "Renamed")
                        #expect(body.type == .savings)
                        #expect(body.openingBalance == 250)
                    }
                )

                let stored = try await Account.find(id, on: app.db)
                #expect(stored?.name == "Renamed")
                #expect(stored?.type == .savings)
                #expect(stored?.openingBalance == 250)
            }
        }

        @Test("editing an Account that doesn't exist 404s")
        func editingMissingAccountFails() async throws {
            try await withAccountsApp { app in
                try await app.testing().test(
                    .PUT, "/v1/accounts/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(UpdateAccountRequest(name: "Doesn't matter", type: .checking))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes an Account")
        func deletesAnAccount() async throws {
            try await withAccountsApp { app in
                let account = Account(name: "Throwaway", type: .cash, openingBalance: 0)
                try await account.save(on: app.db)
                let id = try account.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/accounts/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Account.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting an Account that doesn't exist 404s")
        func deletingMissingAccountFails() async throws {
            try await withAccountsApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/accounts/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("an Account's Balance reflects its opening balance plus every Transaction logged against it")
        func balanceReflectsTransactions() async throws {
            try await withAccountsApp { app in
                let account = Account(name: "Checking", type: .checking, openingBalance: 100)
                try await account.save(on: app.db)
                let accountID = try account.requireID()
                try await Transaction(
                    amount: 30, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000), accountID: accountID
                ).save(on: app.db)
                try await Transaction(
                    amount: 50, type: .income, date: Date(timeIntervalSince1970: 1_800_003_600), accountID: accountID
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/accounts",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([AccountResponse].self)
                        // 100 opening - 30 expense + 50 income == 120.
                        #expect(body.first?.balance == 120)
                        #expect(body.first?.openingBalance == 100)
                    }
                )
            }
        }

        @Test("computes independent Balances for multiple Accounts in one listing")
        func computesIndependentBalancesForMultipleAccounts() async throws {
            try await withAccountsApp { app in
                let checking = Account(name: "Checking", type: .checking, openingBalance: 100)
                let savings = Account(name: "Savings", type: .savings, openingBalance: 500)
                try await checking.save(on: app.db)
                try await savings.save(on: app.db)
                try await Transaction(
                    amount: 40, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000),
                    accountID: try checking.requireID()
                ).save(on: app.db)
                try await Transaction(
                    amount: 25, type: .income, date: Date(timeIntervalSince1970: 1_800_000_000),
                    accountID: try savings.requireID()
                ).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/accounts",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([AccountResponse].self)
                        let byName = Dictionary(uniqueKeysWithValues: body.map { ($0.name, $0) })
                        #expect(byName["Checking"]?.balance == 60)
                        #expect(byName["Savings"]?.balance == 525)
                    }
                )
            }
        }

        @Test("rejects deleting an Account a Transaction still references")
        func deletingAccountWithReferencingTransactionFails() async throws {
            try await withAccountsApp { app in
                let account = Account(name: "Checking", type: .checking, openingBalance: 0)
                try await account.save(on: app.db)
                let id = try account.requireID()
                try await Transaction(
                    amount: 10, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000), accountID: id
                ).save(on: app.db)

                try await app.testing().test(
                    .DELETE, "/v1/accounts/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Account.find(id, on: app.db)
                #expect(stored != nil)
            }
        }
    }
}
