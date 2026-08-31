import Foundation

/// Holds the Finances Reporting screen's state and talks to the backend
/// through a `FinancesReportingAPIClient`, plus an `AccountsAPIClient` to
/// populate the Account picker the two per-Account sections (Balance
/// history, Projected Balance) share — kept separate from
/// `FinancesReportingView` so the view stays a thin rendering of this state
/// (mirrors `TransactionsViewModel`'s multi-client split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class FinancesReportingViewModel: ObservableObject {
    /// The screen's shared date range — `PCCDateRangeControl`
    /// (`FormControls.swift`) reads/writes this directly. `start`/`end`
    /// below are this range's resolved bounds, kept as computed properties
    /// so `load()`/`loadSelectedAccountFigures()` read them exactly as
    /// before.
    @Published public var dateRange: DateRangeSelection
    @Published public private(set) var currentNetWorth: Double = 0
    @Published public private(set) var netWorthTrend: [DailyFigure] = []
    @Published public private(set) var expensesPerDay: [ExpensesPerDayRow] = []
    @Published public private(set) var accounts: [Account] = []
    @Published public var selectedAccountID: UUID?
    @Published public private(set) var accountBalanceHistory: [DailyFigure] = []
    @Published public var projectedBalancePeriod: ProjectedBalancePeriod = .week
    @Published public private(set) var projectedBalance: ProjectedBalance?
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let reportingClient: FinancesReportingAPIClient
    private let accountsClient: AccountsAPIClient

    /// The trailing 30 days through now by default — a Net Worth/Balance
    /// trend or expense-per-day chart reads more informatively over a month
    /// than `WorkHoursViewModel`'s own current-week default, since a
    /// handful of days makes a thin chart. No preset in `DateRangeOption`
    /// means exactly 30 days, so this starts on `.custom` with that range
    /// rather than approximating it with `.thisMonth`/`.lastMonth`.
    public init(reportingClient: FinancesReportingAPIClient, accountsClient: AccountsAPIClient) {
        self.reportingClient = reportingClient
        self.accountsClient = accountsClient
        let today = Calendar.current.startOfDay(for: Date())
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: today) ?? today
        self.dateRange = DateRangeSelection(option: .custom, customStart: thirtyDaysAgo, customEnd: Date())
    }

    private var start: Date { dateRange.resolvedRange.start }
    private var end: Date { dateRange.resolvedRange.end }

    /// Loads every Account-independent figure (current Net Worth, its
    /// trend, expense-per-day) plus the Account list the two per-Account
    /// sections' picker uses, defaulting `selectedAccountID` to the first
    /// Account the first time any load succeeds with one available — then
    /// loads that Account's own figures too.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedNetWorth = reportingClient.fetchCurrentNetWorth()
            async let loadedTrend = reportingClient.fetchNetWorthTrend(start: start, end: end)
            async let loadedExpenses = reportingClient.fetchExpensesPerDay(start: start, end: end)
            async let loadedAccounts = accountsClient.listAccounts()
            currentNetWorth = try await loadedNetWorth
            netWorthTrend = try await loadedTrend
            expensesPerDay = try await loadedExpenses
            accounts = try await loadedAccounts
            if selectedAccountID == nil {
                selectedAccountID = accounts.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Finances Reporting: \(error.localizedDescription)"
        }
        await loadSelectedAccountFigures()
    }

    /// Reloads just the two per-Account sections — Balance history and
    /// Projected Balance — without re-fetching the Account-independent
    /// figures `load()` already has. Called on its own whenever
    /// `selectedAccountID`, `projectedBalancePeriod`, or the shared date
    /// range changes, the same "reload on every control change, no separate
    /// Apply step" shape `WorkHoursView` already uses.
    public func loadSelectedAccountFigures() async {
        guard let accountID = selectedAccountID else {
            accountBalanceHistory = []
            projectedBalance = nil
            return
        }
        do {
            async let loadedHistory = reportingClient.fetchAccountBalanceHistory(accountID: accountID, start: start, end: end)
            async let loadedProjection = reportingClient.fetchProjectedBalance(accountID: accountID, period: projectedBalancePeriod)
            accountBalanceHistory = try await loadedHistory
            projectedBalance = try await loadedProjection
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Account Balance/Projected Balance: \(error.localizedDescription)"
        }
    }
}
