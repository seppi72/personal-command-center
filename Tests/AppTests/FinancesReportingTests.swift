import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

/// Same seam as `AccountTests`/`TransactionTests`: real HTTP requests against
/// a running Vapor app, backed by a real (test) Postgres database. Shares the
/// `accounts`/`transactions` tables with those two suites, so all three clean
/// up on teardown.
extension AppTestSuite {
    @Suite("Finances Reporting", .serialized)
    struct FinancesReportingTests {
        @discardableResult
        private func withFinancesReportingApp<T>(_ test: (Application) async throws -> T) async throws -> T {
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

        @discardableResult
        private func makeAccount(
            _ app: Application, name: String = "Checking", type: AccountType = .checking, openingBalance: Double = 0
        ) async throws -> Account {
            let account = Account(name: name, type: type, openingBalance: openingBalance)
            try await account.save(on: app.db)
            return account
        }

        @discardableResult
        private func makeTransaction(
            _ app: Application, accountID: UUID, amount: Double, type: TransactionType, date: Date
        ) async throws -> Transaction {
            let transaction = Transaction(amount: amount, type: type, date: date, accountID: accountID)
            try await transaction.save(on: app.db)
            return transaction
        }

        private static func isoString(_ date: Date) -> String {
            ISO8601DateFormatter().string(from: date)
        }

        private func rangePath(_ base: String, start: Date, end: Date) -> String {
            "\(base)?start=\(Self.isoString(start))&end=\(Self.isoString(end))"
        }

        // MARK: - Current Net Worth

        @Test("rejects requests without a bearer token")
        func rejectsWithoutToken() async throws {
            try await withFinancesReportingApp { app in
                try await app.testing().test(.GET, "/v1/net-worth", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("current Net Worth sums asset Balances minus liability Balances")
        func currentNetWorthSumsAssetsMinusLiabilities() async throws {
            try await withFinancesReportingApp { app in
                let checking = try await makeAccount(app, name: "Checking", type: .checking, openingBalance: 1000)
                let creditCard = try await makeAccount(app, name: "Credit Card", type: .creditCard, openingBalance: 0)
                try await makeTransaction(
                    app, accountID: try checking.requireID(), amount: 200, type: .expense,
                    date: Date(timeIntervalSince1970: 1_800_000_000)
                )
                try await makeTransaction(
                    app, accountID: try creditCard.requireID(), amount: 150, type: .expense,
                    date: Date(timeIntervalSince1970: 1_800_000_000)
                )
                // Checking: 1000 - 200 = 800 (asset). Credit Card: 0 - 150 =
                // -150 (liability, so it *subtracts* 150 more, i.e. its debt
                // counts against Net Worth). Net Worth = 800 - (-150) = 950.

                try await app.testing().test(
                    .GET, "/v1/net-worth",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(NetWorthResponse.self)
                        #expect(body.netWorth == 950)
                    }
                )
            }
        }

        @Test("current Net Worth is zero with no Accounts")
        func currentNetWorthIsZeroWithNoAccounts() async throws {
            try await withFinancesReportingApp { app in
                try await app.testing().test(
                    .GET, "/v1/net-worth",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(NetWorthResponse.self)
                        #expect(body.netWorth == 0)
                    }
                )
            }
        }

        // MARK: - Net Worth trend

        @Test("Net Worth trend rejects a missing or inverted range")
        func netWorthTrendRejectsBadRange() async throws {
            try await withFinancesReportingApp { app in
                try await app.testing().test(
                    .GET, "/v1/net-worth/trend",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
                let now = Date()
                try await app.testing().test(
                    .GET, rangePath("/v1/net-worth/trend", start: now, end: now.addingTimeInterval(-86400)),
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("Net Worth trend is dense and each day's figure is as of that day's end")
        func netWorthTrendIsDenseAndAsOfDayEnd() async throws {
            try await withFinancesReportingApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let checking = try await makeAccount(app, name: "Checking", type: .checking, openingBalance: 100)
                let creditCard = try await makeAccount(app, name: "Credit Card", type: .creditCard, openingBalance: 0)
                // Dated "today": Checking -30 (expense), Credit Card +40 (a
                // charge, i.e. `.expense` widening the liability).
                try await makeTransaction(
                    app, accountID: try checking.requireID(), amount: 30, type: .expense,
                    date: today.addingTimeInterval(3600)
                )
                try await makeTransaction(
                    app, accountID: try creditCard.requireID(), amount: 40, type: .expense,
                    date: today.addingTimeInterval(3600)
                )
                let rangeEnd = calendar.date(byAdding: .day, value: 2, to: today)!

                try await app.testing().test(
                    .GET, rangePath("/v1/net-worth/trend", start: today, end: rangeEnd),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let rows = try res.content.decode([DailyFigure].self)
                        #expect(rows.count == 2)
                        // Checking: 100 - 30 = 70 (asset). Credit Card: 0 -
                        // 40 = -40 (liability). Net Worth = 70 - (-40) = 110.
                        #expect(rows[0].value == 110)
                        #expect(rows[1].value == 110)
                    }
                )
            }
        }

        @Test("Net Worth trend carries forward a Transaction dated before the range")
        func netWorthTrendCarriesForwardEarlierTransaction() async throws {
            try await withFinancesReportingApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let checking = try await makeAccount(app, name: "Checking", type: .checking, openingBalance: 500)
                try await makeTransaction(
                    app, accountID: try checking.requireID(), amount: 100, type: .expense,
                    date: calendar.date(byAdding: .day, value: -10, to: today)!
                )
                let rangeEnd = calendar.date(byAdding: .day, value: 1, to: today)!

                try await app.testing().test(
                    .GET, rangePath("/v1/net-worth/trend", start: today, end: rangeEnd),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([DailyFigure].self)
                        #expect(rows.count == 1)
                        #expect(rows[0].value == 400)
                    }
                )
            }
        }

        // MARK: - Account Balance history

        @Test("Account Balance history rejects a missing range and a nonexistent Account")
        func balanceHistoryRejectsBadInput() async throws {
            try await withFinancesReportingApp { app in
                let account = try await makeAccount(app)
                let now = Date()

                try await app.testing().test(
                    .GET, "/v1/accounts/\(try account.requireID())/balance-history",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
                try await app.testing().test(
                    .GET, rangePath("/v1/accounts/\(UUID())/balance-history", start: now, end: now.addingTimeInterval(86400)),
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("Account Balance history is dense: a day with nothing logged repeats the running Balance")
        func balanceHistoryIsDense() async throws {
            try await withFinancesReportingApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let account = try await makeAccount(app, openingBalance: 200)
                try await makeTransaction(
                    app, accountID: try account.requireID(), amount: 50, type: .income, date: today.addingTimeInterval(3600)
                )
                let rangeEnd = calendar.date(byAdding: .day, value: 3, to: today)!

                try await app.testing().test(
                    .GET, rangePath("/v1/accounts/\(try account.requireID())/balance-history", start: today, end: rangeEnd),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let rows = try res.content.decode([DailyFigure].self)
                        #expect(rows.count == 3)
                        #expect(rows[0].value == 250)
                        #expect(rows[1].value == 250)
                        #expect(rows[2].value == 250)
                    }
                )
            }
        }

        @Test("Account Balance history only counts that Account's own Transactions")
        func balanceHistoryScopesToOneAccount() async throws {
            try await withFinancesReportingApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let scoped = try await makeAccount(app, name: "Checking", openingBalance: 100)
                let other = try await makeAccount(app, name: "Savings", openingBalance: 100)
                try await makeTransaction(
                    app, accountID: try scoped.requireID(), amount: 10, type: .expense, date: today.addingTimeInterval(3600)
                )
                try await makeTransaction(
                    app, accountID: try other.requireID(), amount: 999, type: .expense, date: today.addingTimeInterval(3600)
                )
                let rangeEnd = calendar.date(byAdding: .day, value: 1, to: today)!

                try await app.testing().test(
                    .GET, rangePath("/v1/accounts/\(try scoped.requireID())/balance-history", start: today, end: rangeEnd),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        let rows = try res.content.decode([DailyFigure].self)
                        #expect(rows.count == 1)
                        #expect(rows[0].value == 90)
                    }
                )
            }
        }

        // MARK: - Expenses per day

        @Test("expenses-per-day sums only expense Transactions, across every Account, per day")
        func expensesPerDaySumsAcrossAccounts() async throws {
            try await withFinancesReportingApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let checking = try await makeAccount(app, name: "Checking", type: .checking)
                let creditCard = try await makeAccount(app, name: "Credit Card", type: .creditCard)
                try await makeTransaction(
                    app, accountID: try checking.requireID(), amount: 20, type: .expense, date: today.addingTimeInterval(3600)
                )
                try await makeTransaction(
                    app, accountID: try creditCard.requireID(), amount: 15, type: .expense, date: today.addingTimeInterval(7200)
                )
                // Income the same day shouldn't be counted as an expense.
                try await makeTransaction(
                    app, accountID: try checking.requireID(), amount: 1000, type: .income, date: today.addingTimeInterval(3600)
                )
                let rangeEnd = calendar.date(byAdding: .day, value: 2, to: today)!

                try await app.testing().test(
                    .GET, rangePath("/v1/expenses-per-day", start: today, end: rangeEnd),
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let rows = try res.content.decode([ExpensesPerDayRow].self)
                        #expect(rows.count == 2)
                        #expect(rows[0].totalExpenses == 35)
                        #expect(rows[1].totalExpenses == 0)
                    }
                )
            }
        }

        // MARK: - Projected Balance

        @Test("Projected Balance rejects a missing or invalid period, and a nonexistent Account")
        func projectedBalanceRejectsBadInput() async throws {
            try await withFinancesReportingApp { app in
                let account = try await makeAccount(app)

                try await app.testing().test(
                    .GET, "/v1/accounts/\(try account.requireID())/projected-balance",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
                try await app.testing().test(
                    .GET, "/v1/accounts/\(try account.requireID())/projected-balance?period=quarter",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
                try await app.testing().test(
                    .GET, "/v1/accounts/\(UUID())/projected-balance?period=week",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("Projected Balance averages trailing-30-day net cash flow and extrapolates it forward")
        func projectedBalanceComputesAverageAndProjection() async throws {
            try await withFinancesReportingApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let account = try await makeAccount(app, openingBalance: 1000)
                let accountID = try account.requireID()
                // Net cash flow over the trailing 30 days: +300 income, -30
                // expense == +270 net, averaging 9/day.
                try await makeTransaction(
                    app, accountID: accountID, amount: 300, type: .income,
                    date: calendar.date(byAdding: .day, value: -5, to: today)!
                )
                try await makeTransaction(
                    app, accountID: accountID, amount: 30, type: .expense,
                    date: calendar.date(byAdding: .day, value: -2, to: today)!
                )

                try await app.testing().test(
                    .GET, "/v1/accounts/\(accountID)/projected-balance?period=week",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectedBalanceResponse.self)
                        #expect(body.period == .week)
                        #expect(body.averageDailyNet == 9)
                        // Today's Balance: 1000 + 300 - 30 = 1270. Remaining
                        // days excludes today itself — today's own net cash
                        // flow is already baked into that 1270, so extrapolating
                        // it a second time via `averageDailyNet` would double it.
                        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                        let expectedRemainingDays = Double(
                            calendar.dateComponents([.day], from: tomorrow, to: calendar.dateInterval(of: .weekOfYear, for: today)!.end).day!
                        )
                        #expect(body.projectedBalance == 1270 + 9 * expectedRemainingDays)
                    }
                )
            }
        }

        @Test("Projected Balance's remaining days excludes today itself, since today's Balance already reflects today")
        func projectedBalanceRemainingDaysExcludesToday() async throws {
            try await withFinancesReportingApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let account = try await makeAccount(app, openingBalance: 0)
                let accountID = try account.requireID()
                // A daily net of exactly 1 over the trailing 30 days: +30
                // net, averaging exactly 1/day.
                try await makeTransaction(
                    app, accountID: accountID, amount: 30, type: .income,
                    date: calendar.date(byAdding: .day, value: -1, to: today)!
                )

                // Independently derived "days remaining in the current month,
                // not counting today" — via day-of-month/days-in-month rather
                // than `Calendar.dateInterval(of:for:)`, the same primitive
                // the implementation itself uses, so this doesn't just mirror
                // the implementation's own formula back at it.
                let daysInMonth = calendar.range(of: .day, in: .month, for: today)!.count
                let dayOfMonth = calendar.component(.day, from: today)
                let expectedRemainingDays = Double(daysInMonth - dayOfMonth)

                try await app.testing().test(
                    .GET, "/v1/accounts/\(accountID)/projected-balance?period=month",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectedBalanceResponse.self)
                        #expect(body.averageDailyNet == 1)
                        // Today's Balance: 0 + 30 = 30.
                        #expect(body.projectedBalance == 30 + 1 * expectedRemainingDays)
                    }
                )
            }
        }

        @Test("Projected Balance excludes a Transaction dated more than 30 days ago")
        func projectedBalanceExcludesOldTransactions() async throws {
            try await withFinancesReportingApp { app in
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let account = try await makeAccount(app, openingBalance: 0)
                let accountID = try account.requireID()
                try await makeTransaction(
                    app, accountID: accountID, amount: 10_000, type: .income,
                    date: calendar.date(byAdding: .day, value: -45, to: today)!
                )

                try await app.testing().test(
                    .GET, "/v1/accounts/\(accountID)/projected-balance?period=month",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(ProjectedBalanceResponse.self)
                        #expect(body.averageDailyNet == 0)
                    }
                )
            }
        }
    }
}
