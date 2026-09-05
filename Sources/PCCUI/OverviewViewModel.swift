import Foundation

/// One point of the Finances card's income/expense/net chart — a period
/// (day, week, or month, depending on how wide the selected range is; see
/// `OverviewViewModel.bucket(_:start:end:)`) paired with that period's total
/// income and expense. Purely a client-side computed presentation type, not
/// a mirror of any backend response — unlike `FinancesReporting.swift`'s
/// `DailyFigure`/`ExpensesPerDayRow`, which really are backend rollups.
public struct FinanceBucket: Identifiable, Sendable {
    public let periodStart: Date
    public let income: Double
    public let expense: Double

    public var id: Date { periodStart }
    /// What's left over for the period — income minus expense. Can be
    /// negative.
    public var net: Double { income - expense }
}

/// Holds the Overview screen's state — a fixed glance at three cards:
/// Finances (Net Worth + an income/expense/net chart over a selectable
/// range), Work (Projects Progress, today's-and-overdue Tasks, and an
/// on-time completion rate), and Productivity (a mini Timer — the one place
/// this screen breaks its own "just a glance" rule, since starting/stopping
/// a Timer from here is the point — plus this week's Work Hours). Composes
/// several existing `APIClient`s directly (mirrors `TimerViewModel`'s own
/// "compose several clients" shape) rather than wrapping the equivalent
/// screen-level view models, so this screen's own filtering/bucketing logic
/// stays out of the general-purpose `WorkViewModel`/`FinancesReportingViewModel`
/// every other screen relies on unfiltered. The Timer itself is a partial
/// exception: the Productivity card reads and mutates the same shared
/// `TimerViewModel` instance the Time Entries screen's own hero timer uses
/// (passed into `OverviewView.init` separately), rather than this view
/// model owning any Timer state of its own.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13
/// (mirrors every other view model in this package).
@MainActor
public final class OverviewViewModel: ObservableObject {
    /// Every Task, loaded unfiltered — backs `projectCompletion`,
    /// `tasksDueToday`/`tasksOverdue`, and `taskCompletionRateWithinDeadline`,
    /// all computed from this one fetch rather than each needing its own.
    @Published public private(set) var tasks: [PCCTask] = []
    @Published public private(set) var projects: [Project] = []
    /// Only fetched/needed to populate `financeBuckets`' underlying
    /// Transactions query — kept for parity with `AccountsAPIClient` calls
    /// elsewhere, though the Finances card itself only shows the current
    /// Net Worth figure and the chart, not a per-Account breakdown.
    @Published public private(set) var accounts: [Account] = []

    /// This week's Work Hours, grouped by day, for the Productivity card's
    /// bar chart.
    @Published public private(set) var workHoursThisWeek: [WorkHoursRow] = []

    /// Every Time Entry, loaded unfiltered — the endpoint takes only
    /// container filters, not a date range, so the window is applied by
    /// `LoggedHours.split` instead (`loadedHoursRange`). Loaded unfiltered
    /// for the same reason `tasks` above is: one fetch feeding a figure this
    /// screen derives several ways.
    @Published public private(set) var timeEntries: [TimeEntry] = []
    /// The half-open window `workHoursThisWeek`/`timeEntries` were loaded
    /// for, kept so `loggedHours` splits over precisely the range that was
    /// fetched rather than recomputing "this week" against a `Date()` that
    /// has since moved on (past midnight, say).
    private var loadedHoursRange: (start: Date, end: Date)?

    @Published public private(set) var currentNetWorth: Double = 0
    /// The Finances card's chart data for whichever range is currently
    /// selected — see `loadFinancesCard()`.
    @Published public private(set) var financeBuckets: [FinanceBucket] = []
    /// The calendar unit `financeBuckets` is grouped by (day/week/month) —
    /// published alongside `financeBuckets` so `OverviewView`'s chart can
    /// pass the right `unit:` to each mark without re-deriving it from
    /// `resolvedRange` itself.
    @Published public private(set) var financeBucketUnit: Calendar.Component = .day
    /// The Finances card's date-range control — `PCCDateRangeControl`
    /// (`FormControls.swift`) reads/writes this directly.
    @Published public var financesDateRange = DateRangeSelection(option: .last7Days)

    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let tasksClient: TasksAPIClient
    private let projectsClient: ProjectsAPIClient
    private let accountsClient: AccountsAPIClient
    private let transactionsClient: TransactionsAPIClient
    private let financesReportingClient: FinancesReportingAPIClient
    private let workHoursClient: WorkHoursAPIClient
    private let timeEntriesClient: TimeEntriesAPIClient

    public init(
        tasksClient: TasksAPIClient,
        projectsClient: ProjectsAPIClient,
        accountsClient: AccountsAPIClient,
        transactionsClient: TransactionsAPIClient,
        financesReportingClient: FinancesReportingAPIClient,
        workHoursClient: WorkHoursAPIClient,
        timeEntriesClient: TimeEntriesAPIClient
    ) {
        self.tasksClient = tasksClient
        self.projectsClient = projectsClient
        self.accountsClient = accountsClient
        self.transactionsClient = transactionsClient
        self.financesReportingClient = financesReportingClient
        self.workHoursClient = workHoursClient
        self.timeEntriesClient = timeEntriesClient
    }

    /// How this week's logged hours divide between the Work and School
    /// dashboards (issue #91).
    ///
    /// Overview is the only screen that can report this: Work filters
    /// Course-owned work out of its tree and School ignores everything else,
    /// so neither shows a true total of the owner's time. Computed through
    /// `LoggedHours.split`, which decides "is this coursework?" with the same
    /// function the School screen totals with, so the parts can't drift from
    /// the screens they describe.
    ///
    /// Zeroed until `load()` has run, rather than optional — the readout
    /// renders zeroed rather than absent, so the card doesn't reflow once
    /// data arrives.
    public var loggedHours: LoggedHoursSplit {
        guard let loadedHoursRange else {
            return LoggedHoursSplit(workSeconds: 0, schoolSeconds: 0)
        }
        return LoggedHours.split(
            timeEntries: timeEntries, tasks: tasks, projects: projects, range: loadedHoursRange)
    }

    /// Each Project paired with the fraction (0–1) of its own Tasks that are
    /// complete — `nil` for a Project with no Tasks yet, since "0 of 0" isn't
    /// meaningfully 0% or 100% done. Backs the Work card's chart. Computed
    /// from `tasks`/`projects`, both already loaded unfiltered, rather than
    /// a separate fetch.
    public var projectCompletion: [(project: Project, fraction: Double)] {
        projects.compactMap { project in
            let projectTasks = tasks.filter { $0.projectID == project.id }
            guard !projectTasks.isEmpty else { return nil }
            let doneCount = projectTasks.filter(\.isComplete).count
            return (project, Double(doneCount) / Double(projectTasks.count))
        }
    }

    /// Incomplete Tasks due today specifically — not overdue (see
    /// `tasksOverdue` for that), the Work card's "Today" list.
    public var tasksDueToday: [PCCTask] {
        tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDateInToday(dueDate) && !task.isComplete
        }
    }

    /// Incomplete Tasks whose due date has already passed — the Work card's
    /// "Overdue" list, kept separate from `tasksDueToday` per the dashboard's
    /// own layout (distinct from the old combined "today or overdue" shape
    /// a single Deadlines widget used).
    public var tasksOverdue: [PCCTask] {
        tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate < Self.startOfToday && !task.isComplete
        }
    }

    /// Of complete Tasks that had both a Deadline and a `completedAt`
    /// timestamp, the fraction completed on or before that Deadline —
    /// `nil` when there's no such Task yet (mirrors `projectCompletion`'s
    /// own "don't claim a rate from zero data" reasoning). `completedAt`
    /// only exists for Tasks completed after that field was introduced
    /// (`PCCTask.completedAt`'s own doc comment), so this rate only reflects
    /// completions from that point forward.
    public var taskCompletionRateWithinDeadline: Double? {
        let eligible = tasks.filter { $0.isComplete && $0.dueDate != nil && $0.completedAt != nil }
        guard !eligible.isEmpty else { return nil }
        let onTime = eligible.filter { $0.completedAt! <= $0.dueDate! }.count
        return Double(onTime) / Double(eligible.count)
    }

    /// The Finances card's status lamp (see `PanelStatus`'s own doc comment
    /// for what the signal generally means): `.critical` when Net Worth
    /// itself has gone negative, `.attention` when Net Worth is still
    /// positive but the selected range's own net (income minus expense) is
    /// negative — spending is outpacing income even if the overall
    /// position is still fine — `.nominal` otherwise.
    public var financesStatus: PanelStatus {
        if currentNetWorth < 0 { return .critical }
        let rangeNet = financeBuckets.reduce(0) { $0 + $1.net }
        return rangeNet < 0 ? .attention : .nominal
    }

    /// The Work card's status lamp: `.critical` when anything is overdue,
    /// `.attention` when nothing's overdue but something's due today,
    /// `.nominal` when neither.
    public var workStatus: PanelStatus {
        if !tasksOverdue.isEmpty { return .critical }
        if !tasksDueToday.isEmpty { return .attention }
        return .nominal
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            let now = Date()
            let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now

            async let loadedTasks = tasksClient.listTasks(projectID: nil, courseID: nil)
            async let loadedProjects = projectsClient.listProjects()
            async let loadedAccounts = accountsClient.listAccounts()
            async let loadedNetWorth = financesReportingClient.fetchCurrentNetWorth()
            async let loadedWorkHours = workHoursClient.fetchWorkHours(groupBy: .day, start: startOfWeek, end: now)
            // Unfiltered, like the Tasks/Projects fetches above: the
            // cross-domain split has to see Client-side and Course-side
            // entries alike, so narrowing by container here would defeat the
            // point of the figure. The endpoint takes no date bound, so the
            // week window is applied in `loggedHours` instead — the same
            // shape `WorkViewModel` already loads Time Entries with.
            async let loadedEntries = timeEntriesClient.listTimeEntries(
                taskID: nil, projectID: nil, clientID: nil, courseID: nil)
            tasks = try await loadedTasks
            projects = try await loadedProjects
            accounts = try await loadedAccounts
            currentNetWorth = try await loadedNetWorth
            workHoursThisWeek = try await loadedWorkHours
            timeEntries = try await loadedEntries
            loadedHoursRange = (start: startOfWeek, end: now)
        }
        await loadFinancesCard()
    }

    /// Reloads just the Finances card's chart — called on its own whenever
    /// `financesDateRange` changes, the same "reload on every control
    /// change, no separate Apply step" shape
    /// `FinancesReportingViewModel.loadSelectedAccountFigures()` already
    /// uses, kept separate from `load()`'s do/catch so a range change
    /// doesn't re-fetch Tasks/Projects/Accounts/Net Worth too.
    public func loadFinancesCard() async {
        do {
            let range = financesDateRange.resolvedRange
            let transactions = try await transactionsClient.listTransactions(
                accountID: nil, start: range.start, end: range.end)
            let unit = Self.bucketUnit(start: range.start, end: range.end)
            financeBucketUnit = unit
            financeBuckets = Self.bucket(transactions, unit: unit)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Finances: \(error.localizedDescription)"
        }
    }

    /// Day for a range of a month or less, week for up to ~4 months, month
    /// for anything wider (e.g. "last year") — keeps the chart from turning
    /// into 365 unreadable daily bars for a year-long range while staying
    /// granular for a short one.
    private static func bucketUnit(start: Date, end: Date) -> Calendar.Component {
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return days <= 31 ? .day : (days <= 120 ? .weekOfYear : .month)
    }

    private static func bucket(_ transactions: [Transaction], unit: Calendar.Component) -> [FinanceBucket] {
        let calendar = Calendar.current
        var totals: [Date: (income: Double, expense: Double)] = [:]
        for transaction in transactions {
            guard let periodStart = calendar.dateInterval(of: unit, for: transaction.date)?.start else { continue }
            var entry = totals[periodStart] ?? (income: 0, expense: 0)
            switch transaction.type {
            case .income: entry.income += transaction.amount
            case .expense: entry.expense += transaction.amount
            }
            totals[periodStart] = entry
        }
        return totals.keys.sorted().map { periodStart in
            let entry = totals[periodStart]!
            return FinanceBucket(periodStart: periodStart, income: entry.income, expense: entry.expense)
        }
    }

    private static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Runs a fetch against every published property this view model owns,
    /// keeping success/failure handling in one shape instead of scattered
    /// copies — mirrors `TimerViewModel.run`/`TransactionsViewModel.run`.
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Overview: \(error.localizedDescription)"
        }
    }
}
