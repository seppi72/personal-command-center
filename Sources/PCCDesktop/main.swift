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

struct DashboardView: View {
    var body: some View {
        TabView {
            ProjectsView(
                viewModel: ProjectsViewModel(
                    client: projectsClient, clientsClient: clientsClient, sprintsClient: sprintsClient)
            )
            .tabItem { Label("Projects", systemImage: "folder") }

            TasksView(
                viewModel: TasksViewModel(
                    tasksClient: tasksClient, projectsClient: projectsClient, coursesClient: coursesClient)
            )
            .tabItem { Label("Tasks", systemImage: "checkmark.circle") }

            DeadlinesView(viewModel: DeadlinesViewModel(client: deadlinesClient))
                .tabItem { Label("Deadlines", systemImage: "clock") }

            CalendarView(
                viewModel: CalendarViewModel(
                    commitmentsClient: personalCommitmentsClient,
                    mirroredEventsClient: mirroredCalendarEventsClient)
            )
            .tabItem { Label("Calendar", systemImage: "calendar") }

            PersonalCommitmentsView(viewModel: PersonalCommitmentsViewModel(client: personalCommitmentsClient))
                .tabItem { Label("Commitments", systemImage: "person.crop.circle") }

            ClientsView(viewModel: ClientsViewModel(client: clientsClient))
                .tabItem { Label("Clients", systemImage: "building.2") }

            CourseView(
                viewModel: CoursesViewModel(
                    client: coursesClient, tasksClient: tasksClient, projectsClient: projectsClient)
            )
            .tabItem { Label("Courses", systemImage: "graduationcap") }

            TimeEntriesView(
                viewModel: TimeEntriesViewModel(
                    timeEntriesClient: timeEntriesClient, tasksClient: tasksClient,
                    projectsClient: projectsClient, clientsClient: clientsClient, coursesClient: coursesClient)
            )
            .tabItem { Label("Time Entries", systemImage: "stopwatch") }

            TimerView(
                viewModel: TimerViewModel(
                    timeEntriesClient: timeEntriesClient, tasksClient: tasksClient,
                    projectsClient: projectsClient, clientsClient: clientsClient, coursesClient: coursesClient)
            )
            .tabItem { Label("Timer", systemImage: "play.circle") }

            WorkHoursView(viewModel: WorkHoursViewModel(client: workHoursClient))
                .tabItem { Label("Work Hours", systemImage: "hourglass") }

            AccountsView(viewModel: AccountsViewModel(client: accountsClient))
                .tabItem { Label("Accounts", systemImage: "dollarsign.circle") }

            TransactionsView(
                viewModel: TransactionsViewModel(
                    transactionsClient: transactionsClient, accountsClient: accountsClient,
                    categoriesClient: categoriesClient, subcategoriesClient: subcategoriesClient)
            )
            .tabItem { Label("Transactions", systemImage: "creditcard") }

            CategoriesView(
                viewModel: CategoriesViewModel(client: categoriesClient, subcategoriesClient: subcategoriesClient)
            )
            .tabItem { Label("Categories", systemImage: "tag") }

            FinancesReportingView(
                viewModel: FinancesReportingViewModel(
                    reportingClient: financesReportingClient, accountsClient: accountsClient)
            )
            .tabItem { Label("Finances", systemImage: "chart.line.uptrend.xyaxis") }

            NotificationsView(viewModel: NotificationsViewModel(client: notificationsClient))
                .tabItem { Label("Notifications", systemImage: "bell") }

            AutomationLogView(viewModel: AutomationLogViewModel(client: automationLogsClient))
                .tabItem { Label("Automation Log", systemImage: "list.bullet.rectangle") }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct PCCDesktopApp: App {
    var body: some Scene {
        WindowGroup("Personal Command Center") {
            DashboardView()
        }
    }
}

PCCDesktopApp.main()
