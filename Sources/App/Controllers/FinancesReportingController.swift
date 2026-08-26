import Fluent
import Vapor

struct NetWorthResponse: Content {
    let netWorth: Double
}

/// One day of a dense day-by-day series (`FinancesReportingController`'s own
/// doc comment) — `Account.balance-history` and `net-worth/trend` share this
/// exact shape (`{date, value}`), unlike `WorkHoursRow`'s five differently-
/// keyed cases, so one `Content` type covers both rather than two near-
/// identical structs.
struct DailyFigure: Content {
    let date: Date
    let value: Double
}

struct ExpensesPerDayRow: Content {
    let date: Date
    let totalExpenses: Double
}

/// The two periods Projected Balance can extrapolate across (`CONTEXT.md`).
/// Raw values are camelCase query-string values, matching `WorkHoursGroupBy`'s
/// own convention.
enum ProjectedBalancePeriod: String, Codable, Sendable {
    case week, month
}

struct ProjectedBalanceResponse: Content {
    let averageDailyNet: Double
    let projectedBalance: Double
    let period: ProjectedBalancePeriod
}

/// Ticket #40: Finances Reporting — read-only, computed rollups over
/// Account/Transaction (`CONTEXT.md`'s Net Worth/Projected Balance entries).
/// Mirrors `WorkHoursController`'s "one feature family, several read
/// endpoints sharing the same range/dense-day query pattern" shape rather
/// than one endpoint with a `groupBy`-style switch, since these five figures
/// don't share a single response shape the way Work Hours' five `groupBy`
/// values do.
struct FinancesReportingController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("net-worth", use: currentNetWorth)
        routes.get("net-worth", "trend", use: netWorthTrend)
        routes.get("expenses-per-day", use: expensesPerDay)
        routes.grouped("accounts").group(":accountID") { account in
            account.get("balance-history", use: accountBalanceHistory)
            account.get("projected-balance", use: projectedBalance)
        }
    }

    /// Current Net Worth (`CONTEXT.md`): every asset Account's Balance minus
    /// every liability Account's Balance, computed live at request time —
    /// same "load every Account, load every net Transaction sum once" shape
    /// `AccountController.index` already uses, not a fresh query per
    /// Account.
    func currentNetWorth(req: Request) async throws -> NetWorthResponse {
        let accounts = try await Account.query(on: req.db).all()
        let netAmounts = try await Transaction.netAmountsByAccount(on: req.db)
        let netWorth = accounts.reduce(into: 0.0) { total, account in
            guard let id = account.id else { return }
            let balance = account.openingBalance + (netAmounts[id] ?? 0)
            total += Self.signedForNetWorth(balance, classification: account.type.classification)
        }
        return NetWorthResponse(netWorth: netWorth)
    }

    /// Net Worth trend: one dense `[start, end)` row per calendar day, each
    /// day's figure computed as of that day's end (`CONTEXT.md`) — every
    /// asset Account's as-of-that-day Balance minus every liability
    /// Account's, summed. Built from one Account query and one Transaction
    /// query total, not one Transaction query per Account or per day
    /// (`Self.cumulativeSeries`'s own doc comment).
    func netWorthTrend(req: Request) async throws -> [DailyFigure] {
        let (start, end) = try Self.validatedRange(req)
        let accounts = try await Account.query(on: req.db).all()
        let transactionsByAccount = try await Self.transactionsGroupedByAccount(on: req.db)
        let days = Self.denseDays(start: start, end: end)
        var totals = [Double](repeating: 0, count: days.count)
        for account in accounts {
            guard let id = account.id else { continue }
            let sign = Self.signMultiplier(for: account.type.classification)
            let series = Self.cumulativeSeries(
                openingTotal: account.openingBalance,
                transactions: transactionsByAccount[id] ?? [],
                days: days
            )
            for (index, dayTotal) in series.enumerated() {
                totals[index] += sign * dayTotal
            }
        }
        return zip(days, totals).map { DailyFigure(date: $0, value: $1) }
    }

    /// Expense-per-day: one dense `[start, end)` row per calendar day, each
    /// day's figure the sum of every expense-type Transaction *dated that
    /// day* — across every Account regardless of Type (`CONTEXT.md`), unlike
    /// `netWorthTrend`/`accountBalanceHistory` this is not cumulative, the
    /// same "one day's total, not a running total" shape
    /// `WorkHoursController.dayRows` already has for its own `groupBy=day`.
    func expensesPerDay(req: Request) async throws -> [ExpensesPerDayRow] {
        let (start, end) = try Self.validatedRange(req)
        let expenses = try await Transaction.query(on: req.db)
            .filter(\.$typeRawValue == TransactionType.expense.rawValue)
            .filter(\.$date >= start)
            .filter(\.$date < end)
            .all()
        let calendar = Calendar.current
        var totalsByDay: [Date: Double] = [:]
        for expense in expenses {
            let day = calendar.startOfDay(for: expense.date)
            totalsByDay[day, default: 0] += expense.amount
        }
        return Self.denseDays(start: start, end: end).map { day in
            ExpensesPerDayRow(date: day, totalExpenses: totalsByDay[day] ?? 0)
        }
    }

    /// One Account's Balance over `[start, end)`, each day's figure computed
    /// as of that day's end (`CONTEXT.md`) — the per-Account counterpart to
    /// `netWorthTrend`. A Transaction dated before `start` still counts
    /// toward every day's figure (`Self.cumulativeSeries` walks every
    /// Transaction against this Account, not just ones dated inside the
    /// range) since a day's Balance is opening-balance-forward, not
    /// range-relative.
    func accountBalanceHistory(req: Request) async throws -> [DailyFigure] {
        guard let account = try await findAccount(req: req) else {
            throw Abort(.notFound)
        }
        let (start, end) = try Self.validatedRange(req)
        let accountID = try account.requireID()
        let transactions = try await Transaction.query(on: req.db)
            .filter(\.$account.$id == accountID)
            .all()
        let days = Self.denseDays(start: start, end: end)
        let series = Self.cumulativeSeries(openingTotal: account.openingBalance, transactions: transactions, days: days)
        return zip(days, series).map { DailyFigure(date: $0, value: $1) }
    }

    /// Projected Balance (`CONTEXT.md`): trailing-30-day average daily net
    /// cash flow (income minus expenses — `Transaction.signedAmount` already
    /// carries that sign), extrapolated across the remaining days of
    /// `period`. "Today's Balance" reuses the same as-of-day-end formula
    /// `accountBalanceHistory`/`netWorthTrend` use (`Transaction.netAmount(forAccount:asOf:)`)
    /// rather than `AccountController`'s plain `netAmount` (every Transaction
    /// regardless of date) — one shared "Balance as of a day" definition
    /// everywhere in this feature family, not two that could quietly
    /// disagree if a future-dated Transaction ever existed.
    func projectedBalance(req: Request) async throws -> ProjectedBalanceResponse {
        guard let account = try await findAccount(req: req) else {
            throw Abort(.notFound)
        }
        let period = try Self.validatedPeriod(req)
        let accountID = try account.requireID()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) else {
            preconditionFailure("date(byAdding:) failed for a plain -30 days")
        }
        let trailingTransactions = try await Transaction.query(on: req.db)
            .filter(\.$account.$id == accountID)
            .filter(\.$date >= thirtyDaysAgo)
            .filter(\.$date < today)
            .all()
        let netCashFlow = trailingTransactions.reduce(0) { $0 + $1.signedAmount }
        let averageDailyNet = netCashFlow / 30
        let todaysBalance = account.openingBalance + (try await Transaction.netAmount(forAccount: accountID, asOf: today, on: req.db))
        let remainingDays = try Self.remainingDays(in: period, from: today)
        let projected = todaysBalance + averageDailyNet * Double(remainingDays)
        return ProjectedBalanceResponse(averageDailyNet: averageDailyNet, projectedBalance: projected, period: period)
    }

    // MARK: - Shared range/day helpers

    /// `start`/`end` travel as plain ISO 8601 query-string values, parsed by
    /// hand — same `WorkHoursController.validatedRange` reasoning: Vapor's
    /// query decoder defaults `Date` to `secondsSince1970`, unlike its JSON
    /// body decoder. `[start, end)`, both required, mirroring
    /// `WorkHoursController`'s own error shape exactly.
    private static func validatedRange(_ req: Request) throws -> (start: Date, end: Date) {
        let formatter = ISO8601DateFormatter()
        guard
            let startRaw = req.query[String.self, at: "start"],
            let start = formatter.date(from: startRaw)
        else {
            throw Abort(.badRequest, reason: "start is required and must be an ISO 8601 date")
        }
        guard
            let endRaw = req.query[String.self, at: "end"],
            let end = formatter.date(from: endRaw)
        else {
            throw Abort(.badRequest, reason: "end is required and must be an ISO 8601 date")
        }
        guard end > start else {
            throw Abort(.badRequest, reason: "end must be after start")
        }
        return (start, end)
    }

    private static func validatedPeriod(_ req: Request) throws -> ProjectedBalancePeriod {
        guard
            let raw = req.query[String.self, at: "period"],
            let period = ProjectedBalancePeriod(rawValue: raw)
        else {
            throw Abort(.badRequest, reason: "period must be one of week, month")
        }
        return period
    }

    /// `start`'s calendar day through `end`'s (exclusive), inclusive of
    /// every day in between — the same dense-range walk
    /// `WorkHoursController.dayRows` already does.
    private static func denseDays(start: Date, end: Date) -> [Date] {
        let calendar = Calendar.current
        var days: [Date] = []
        var current = calendar.startOfDay(for: start)
        while current < end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    /// Every Transaction, keyed by `account_id` — one query total, so
    /// `netWorthTrend` doesn't issue one Transaction query per Account.
    private static func transactionsGroupedByAccount(on database: any Database) async throws -> [UUID: [Transaction]] {
        try await Transaction.query(on: database).all().reduce(into: [:]) { grouped, transaction in
            grouped[transaction.$account.id, default: []].append(transaction)
        }
    }

    /// A running-balance cumulative series aligned to `days`: `days[i]`'s
    /// figure is `openingTotal` plus every one of `transactions` dated on or
    /// before `days[i]`'s end. `transactions` need not be pre-filtered to
    /// `days`' own range — a Transaction dated before `days[0]` still
    /// contributes to every day's figure, the same "opening-balance-forward,
    /// not range-relative" reasoning `accountBalanceHistory`'s own doc
    /// comment gives. Walks `transactions` (sorted once, ascending) with a
    /// single advancing index alongside `days` — O(n log n) total rather
    /// than the O(days × transactions) a naive per-day filter-and-sum would
    /// cost, the dense-series analog of `AccountController`'s own "load
    /// once, aggregate in memory" move.
    private static func cumulativeSeries(openingTotal: Double, transactions: [Transaction], days: [Date]) -> [Double] {
        let calendar = Calendar.current
        let sorted = transactions.sorted { $0.date < $1.date }
        var index = 0
        var runningTotal = openingTotal
        var series: [Double] = []
        series.reserveCapacity(days.count)
        for day in days {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else {
                series.append(runningTotal)
                continue
            }
            while index < sorted.count, sorted[index].date < dayEnd {
                runningTotal += sorted[index].signedAmount
                index += 1
            }
            series.append(runningTotal)
        }
        return series
    }

    private static func signMultiplier(for classification: AccountClassification) -> Double {
        classification == .asset ? 1 : -1
    }

    private static func signedForNetWorth(_ balance: Double, classification: AccountClassification) -> Double {
        balance * signMultiplier(for: classification)
    }

    /// Remaining days in `period`'s current instance, counted from
    /// *tomorrow* through the period's last day (inclusive) — `today` itself
    /// is excluded because `todaysBalance` already reflects today's own
    /// Transactions (`Transaction.netAmount(forAccount:asOf:)`); counting
    /// today again here would double it, once as fact and once as an extra
    /// `averageDailyNet` on top. Tomorrow through
    /// `calendar.dateInterval(of:for:)`'s exclusive `end` (the start of the
    /// *next* period) is exactly that count.
    private static func remainingDays(in period: ProjectedBalancePeriod, from today: Date) throws -> Int {
        let calendar = Calendar.current
        let component: Calendar.Component = period == .week ? .weekOfYear : .month
        guard let interval = calendar.dateInterval(of: component, for: today) else {
            preconditionFailure("dateInterval(of:for:) failed for a plain week/month component")
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            preconditionFailure("date(byAdding:) failed for a plain +1 day")
        }
        guard let days = calendar.dateComponents([.day], from: tomorrow, to: interval.end).day else {
            preconditionFailure("dateComponents day count failed for two Calendar-derived dates")
        }
        return max(days, 0)
    }

    private func findAccount(req: Request) async throws -> Account? {
        guard let id = req.parameters.get("accountID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Account.find(id, on: req.db)
    }
}
