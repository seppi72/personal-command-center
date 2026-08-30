import Foundation

/// Holds the Overview screen's state — a fixed, read-only glance at three
/// things: the active Timer, today's-and-overdue Deadlines, and the last
/// week's Transactions. Composes several existing `APIClient`s directly
/// (mirrors `TimerViewModel`'s own "compose several clients" shape) rather
/// than wrapping the three existing screen-level view models, so this
/// screen's own filtering/capping logic ("just today's items", "just the
/// last 5") stays out of the general-purpose `DeadlinesViewModel`/
/// `TimerViewModel`/`TransactionsViewModel` that every other screen relies
/// on unfiltered.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13
/// (mirrors every other view model in this package).
@MainActor
public final class OverviewViewModel: ObservableObject {
    /// Today's-and-overdue Deadlines, capped to the 5 nearest — see `load()`.
    @Published public private(set) var upcomingDeadlines: [DeadlineItem] = []
    /// How many items `upcomingDeadlines` was capped down from, so the view
    /// can show a "+N more" row; `0` when nothing was cut.
    @Published public private(set) var additionalDeadlinesCount = 0

    @Published public private(set) var activeTimer: TimeEntry?
    /// The active timer's container picker data — only fetched/needed to
    /// label `activeTimer`, same four lists `TimerViewModel` already loads.
    @Published public private(set) var tasks: [PCCTask] = []
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var clients: [PCCClient] = []
    @Published public private(set) var courses: [Course] = []

    /// The last 7 days' Transactions, capped to the 5 most recent — see
    /// `load()`.
    @Published public private(set) var recentTransactions: [Transaction] = []
    /// How many items `recentTransactions` was capped down from; `0` when
    /// nothing was cut.
    @Published public private(set) var additionalTransactionsCount = 0
    /// Only fetched/needed to label a Transaction's Account, same as
    /// `TransactionsView.accountName(for:)`.
    @Published public private(set) var accounts: [Account] = []

    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    /// Each section is capped to this many rows, with the rest surfaced as a
    /// "+N more" count instead — an unbounded overdue-Deadlines or
    /// busy-week-of-Transactions list would defeat the point of a glance
    /// screen.
    private static let sectionCap = 5
    /// The Transactions section's time window.
    private static let recentTransactionsWindow: TimeInterval = 7 * 24 * 60 * 60

    private let deadlinesClient: DeadlinesAPIClient
    private let timeEntriesClient: TimeEntriesAPIClient
    private let tasksClient: TasksAPIClient
    private let projectsClient: ProjectsAPIClient
    private let clientsClient: ClientsAPIClient
    private let coursesClient: CoursesAPIClient
    private let transactionsClient: TransactionsAPIClient
    private let accountsClient: AccountsAPIClient

    public init(
        deadlinesClient: DeadlinesAPIClient,
        timeEntriesClient: TimeEntriesAPIClient,
        tasksClient: TasksAPIClient,
        projectsClient: ProjectsAPIClient,
        clientsClient: ClientsAPIClient,
        coursesClient: CoursesAPIClient,
        transactionsClient: TransactionsAPIClient,
        accountsClient: AccountsAPIClient
    ) {
        self.deadlinesClient = deadlinesClient
        self.timeEntriesClient = timeEntriesClient
        self.tasksClient = tasksClient
        self.projectsClient = projectsClient
        self.clientsClient = clientsClient
        self.coursesClient = coursesClient
        self.transactionsClient = transactionsClient
        self.accountsClient = accountsClient
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            let windowStart = Date().addingTimeInterval(-Self.recentTransactionsWindow)
            async let loadedDeadlines = deadlinesClient.listDeadlines()
            async let loadedTimer = timeEntriesClient.getActiveTimer()
            async let loadedTasks = tasksClient.listTasks(projectID: nil, courseID: nil)
            async let loadedProjects = projectsClient.listProjects()
            async let loadedClients = clientsClient.listClients()
            async let loadedCourses = coursesClient.listCourses()
            async let loadedTransactions = transactionsClient.listTransactions(
                accountID: nil, start: windowStart, end: nil)
            async let loadedAccounts = accountsClient.listAccounts()

            let deadlines = try await loadedDeadlines
            activeTimer = try await loadedTimer
            tasks = try await loadedTasks
            projects = try await loadedProjects
            clients = try await loadedClients
            courses = try await loadedCourses
            let transactions = try await loadedTransactions
            accounts = try await loadedAccounts

            let dueTodayOrOverdue = Self.dueTodayOrOverdue(deadlines)
            upcomingDeadlines = Array(dueTodayOrOverdue.prefix(Self.sectionCap))
            additionalDeadlinesCount = max(0, dueTodayOrOverdue.count - Self.sectionCap)

            let sortedTransactions = transactions.sorted { $0.date > $1.date }
            recentTransactions = Array(sortedTransactions.prefix(Self.sectionCap))
            additionalTransactionsCount = max(0, sortedTransactions.count - Self.sectionCap)
        }
    }

    /// `items` filtered to what's due today or already past due, and not
    /// already complete — the backend already orders `items` by Deadline
    /// proximity with undated items included (`DeadlinesViewModel`'s own
    /// comment on `DeadlinesAPIClient.listDeadlines()`), so this only needs
    /// to filter, not re-sort. `isComplete` is `nil` for a Project/Course
    /// (no such concept at that level, per `DeadlineItem`'s own doc comment)
    /// so those never get excluded here — an overdue Project/Course has no
    /// way to stop being "overdue" except by its Deadline being edited or
    /// cleared on the Projects/Courses screen, the same as the standalone
    /// Deadlines screen already behaves; not a gap this screen introduces.
    private static func dueTodayOrOverdue(_ items: [DeadlineItem]) -> [DeadlineItem] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)
        return items.filter { item in
            guard let dueDate = item.dueDate else { return false }
            return dueDate < endOfToday && item.isComplete != true
        }
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
