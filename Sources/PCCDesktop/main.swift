import SwiftUI
import PCCUI

// Dev-only Mac preview app — see the comment on the `PCCDesktop` target in
// Package.swift. Not an Xcode app target: this file is what SwiftUI's `App`
// protocol needs to run as a bare `swift run` executable (an explicit
// `.main()` call rather than `@main`, since `@main` isn't permitted in a
// file named `main.swift`).
//
// Points at the backend from environment variables so nothing here needs
// editing to match a given machine's setup:
//   PCC_BASE_URL    - defaults to http://127.0.0.1:8080
//   PCC_AUTH_TOKEN  - defaults to "mac-token"; must be one of the
//                     comma-separated values the backend was started with
//                     (`AUTH_TOKENS`, see README) or every request 401s.

let environment = ProcessInfo.processInfo.environment
let baseURL = URL(string: environment["PCC_BASE_URL"] ?? "http://127.0.0.1:8080")!
let bearerToken = environment["PCC_AUTH_TOKEN"] ?? "mac-token"

// One instance per API client, shared across whichever screens need it —
// mirrors how a real app target would wire this up per the README's
// "Consumers (Mac/iOS)" section.
let projectsClient = URLSessionProjectsAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let tasksClient = URLSessionTasksAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let deadlinesClient = URLSessionDeadlinesAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let personalCommitmentsClient = URLSessionPersonalCommitmentsAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let mirroredCalendarEventsClient = URLSessionMirroredCalendarEventsAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let automationLogsClient = URLSessionAutomationLogsAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let clientsClient = URLSessionClientsAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let sprintsClient = URLSessionSprintsAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let coursesClient = URLSessionCoursesAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let timeEntriesClient = URLSessionTimeEntriesAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let workHoursClient = URLSessionWorkHoursAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let accountsClient = URLSessionAccountsAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let transactionsClient = URLSessionTransactionsAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let categoriesClient = URLSessionCategoriesAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let subcategoriesClient = URLSessionSubcategoriesAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let financesReportingClient = URLSessionFinancesReportingAPIClient(baseURL: baseURL, bearerToken: bearerToken)
let notificationsClient = URLSessionNotificationsAPIClient(baseURL: baseURL, bearerToken: bearerToken)

// One instance per screen's view model, constructed once here (rather than
// inline in `DashboardView.body`) so switching the sidebar selection
// doesn't rebuild — and re-fetch, and lose scroll/sheet state for — the
// screen you're navigating away from. Top-level code in `main.swift` runs
// on the main actor, same as these `@MainActor` view models require.
let projectsViewModel = ProjectsViewModel(
    client: projectsClient, clientsClient: clientsClient, sprintsClient: sprintsClient, tasksClient: tasksClient)
let tasksViewModel = TasksViewModel(tasksClient: tasksClient, projectsClient: projectsClient, coursesClient: coursesClient)
let deadlinesViewModel = DeadlinesViewModel(client: deadlinesClient)
let calendarViewModel = CalendarViewModel(
    commitmentsClient: personalCommitmentsClient, mirroredEventsClient: mirroredCalendarEventsClient, coursesClient: coursesClient)
let personalCommitmentsViewModel = PersonalCommitmentsViewModel(client: personalCommitmentsClient, coursesClient: coursesClient)
let clientsViewModel = ClientsViewModel(client: clientsClient)
let coursesViewModel = CoursesViewModel(
    client: coursesClient, tasksClient: tasksClient, projectsClient: projectsClient, commitmentsClient: personalCommitmentsClient)
let timeEntriesViewModel = TimeEntriesViewModel(
    timeEntriesClient: timeEntriesClient, tasksClient: tasksClient, projectsClient: projectsClient,
    clientsClient: clientsClient, coursesClient: coursesClient)
let timerViewModel = TimerViewModel(
    timeEntriesClient: timeEntriesClient, tasksClient: tasksClient, projectsClient: projectsClient,
    clientsClient: clientsClient, coursesClient: coursesClient)
let workHoursViewModel = WorkHoursViewModel(client: workHoursClient)
let accountsViewModel = AccountsViewModel(client: accountsClient)
let transactionsViewModel = TransactionsViewModel(
    transactionsClient: transactionsClient, accountsClient: accountsClient,
    categoriesClient: categoriesClient, subcategoriesClient: subcategoriesClient)
let categoriesViewModel = CategoriesViewModel(client: categoriesClient, subcategoriesClient: subcategoriesClient)
let financesReportingViewModel = FinancesReportingViewModel(
    reportingClient: financesReportingClient, accountsClient: accountsClient)
let notificationsViewModel = NotificationsViewModel(client: notificationsClient)
let automationLogViewModel = AutomationLogViewModel(client: automationLogsClient)
let overviewViewModel = OverviewViewModel(
    tasksClient: tasksClient, projectsClient: projectsClient, accountsClient: accountsClient,
    transactionsClient: transactionsClient, financesReportingClient: financesReportingClient,
    workHoursClient: workHoursClient)

/// One case per sidebar row. `CaseIterable` order is display order within
/// whichever `SidebarSection` the screen belongs to (see below) — it no
/// longer determines the sidebar's overall top-to-bottom order once there's
/// more than one section.
enum Screen: String, CaseIterable, Identifiable {
    case overview
    case projects, tasks, deadlines, calendar, commitments, clients, courses
    case timeEntries, timer, workHours, accounts, transactions, categories
    case financesReporting, notifications, automationLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .projects: "Projects"
        case .tasks: "Tasks"
        case .deadlines: "Deadlines"
        case .calendar: "Calendar"
        case .commitments: "Commitments"
        case .clients: "Clients"
        case .courses: "Courses"
        case .timeEntries: "Time Entries"
        case .timer: "Timer"
        case .workHours: "Work Hours"
        case .accounts: "Accounts"
        case .transactions: "Transactions"
        case .categories: "Categories"
        case .financesReporting: "Finances"
        case .notifications: "Notifications"
        case .automationLog: "Automation Log"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .projects: "folder"
        case .tasks: "checkmark.circle"
        case .deadlines: "clock"
        case .calendar: "calendar"
        case .commitments: "person.crop.circle"
        case .clients: "building.2"
        case .courses: "graduationcap"
        case .timeEntries: "stopwatch"
        case .timer: "play.circle"
        case .workHours: "hourglass"
        case .accounts: "dollarsign.circle"
        case .transactions: "creditcard"
        case .categories: "tag"
        case .financesReporting: "chart.line.uptrend.xyaxis"
        case .notifications: "bell"
        case .automationLog: "list.bullet.rectangle"
        }
    }
}

/// Groups the sidebar's 16 screens under a handful of headings so the list
/// is scannable instead of one flat run — purely a presentation grouping,
/// with no effect on `Screen`'s own identity or on `detail(for:)`.
enum SidebarSection: CaseIterable {
    case work, planning, clients, finances, system

    var title: String {
        switch self {
        case .work: "Work"
        case .planning: "Planning"
        case .clients: "Clients"
        case .finances: "Finances"
        case .system: "System"
        }
    }

    var screens: [Screen] {
        switch self {
        case .work: [.projects, .tasks, .timeEntries, .timer, .workHours]
        case .planning: [.deadlines, .calendar, .commitments, .courses]
        case .clients: [.clients]
        case .finances: [.accounts, .transactions, .categories, .financesReporting]
        case .system: [.notifications, .automationLog]
        }
    }
}

struct DashboardView: View {
    @State private var selection: Screen? = .overview

    /// Whole-app Light/Dark override — a plain on/off switch (no
    /// "follow system" third option), persisted so it survives a relaunch.
    /// Forces `.preferredColorScheme` below rather than leaving every
    /// screen to follow the Mac's system appearance the way this app used
    /// to; `GlassDesignSystem.swift`'s `GlassBackground`/`GlassSurface` both
    /// read `@Environment(\.colorScheme)` (which this sets) rather than a
    /// system dynamic color, so they pick this override up everywhere.
    @AppStorage("pcc.isDarkMode") private var isDarkMode = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                // Pinned above the grouped sections, not inside a `Section`
                // of its own — Overview is cross-cutting (it summarizes
                // every other section at once), not one more category
                // alongside Work/Planning/Clients/Finances/System.
                Label(Screen.overview.title, systemImage: Screen.overview.systemImage)
                    .tag(Screen.overview)
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Section(section.title) {
                        ForEach(section.screens) { screen in
                            Label(screen.title, systemImage: screen.systemImage)
                                .tag(screen)
                        }
                    }
                }
                // Pinned below the grouped sections — the sidebar's only
                // non-navigating row (every `Screen` row above routes
                // through `detail(for:)`; this one just flips a stored
                // preference), so it's its own `Section` rather than one
                // more `Screen` case that would need a `detail(for:)`
                // branch with nothing to actually navigate to.
                Section("Settings") {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                }
            }
            .navigationTitle("Personal Command Center")
        } detail: {
            detail(for: selection ?? .overview)
        }
        .frame(minWidth: 1000, maxWidth: .infinity, minHeight: 650, maxHeight: .infinity)
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    @ViewBuilder
    private func detail(for screen: Screen) -> some View {
        switch screen {
        case .overview:
            OverviewView(
                viewModel: overviewViewModel,
                timerViewModel: timerViewModel,
                onTapFinances: { selection = .financesReporting },
                onTapProjects: { selection = .projects },
                onTapTasks: { selection = .tasks }
            )
        case .projects: ProjectsView(viewModel: projectsViewModel)
        case .tasks: TasksView(viewModel: tasksViewModel)
        case .deadlines: DeadlinesView(viewModel: deadlinesViewModel)
        case .calendar: CalendarView(viewModel: calendarViewModel)
        case .commitments: PersonalCommitmentsView(viewModel: personalCommitmentsViewModel)
        case .clients: ClientsView(viewModel: clientsViewModel)
        case .courses: CourseView(viewModel: coursesViewModel)
        case .timeEntries: TimeEntriesView(viewModel: timeEntriesViewModel)
        case .timer: TimerView(viewModel: timerViewModel)
        case .workHours: WorkHoursView(viewModel: workHoursViewModel)
        case .accounts: AccountsView(viewModel: accountsViewModel)
        case .transactions: TransactionsView(viewModel: transactionsViewModel)
        case .categories: CategoriesView(viewModel: categoriesViewModel)
        case .financesReporting: FinancesReportingView(viewModel: financesReportingViewModel)
        case .notifications: NotificationsView(viewModel: notificationsViewModel)
        case .automationLog: AutomationLogView(viewModel: automationLogViewModel)
        }
    }
}

struct PCCDesktopApp: App {
    var body: some Scene {
        WindowGroup("Personal Command Center") {
            DashboardView()
        }
        // Without this, the window could only be maximized, not dragged
        // larger/smaller from a corner or edge — `.contentMinSize` tells
        // SwiftUI the window resizes freely down to `DashboardView`'s own
        // declared minimum (`.frame(minWidth:minHeight:)`) rather than
        // leaving resizability to inference alone.
        .windowResizability(.contentMinSize)
    }
}

PCCDesktopApp.main()
