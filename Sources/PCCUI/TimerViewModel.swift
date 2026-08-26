import Foundation

/// Holds the live-timer control's state (ticket #28) and talks to the
/// backend through a `TimeEntriesAPIClient`'s timer endpoints, plus
/// `TasksAPIClient`/`ProjectsAPIClient`/`ClientsAPIClient`/`CoursesAPIClient`
/// to populate the container picker used when starting one — kept separate
/// from `TimeEntriesViewModel`, which owns the full Time Entry list/CRUD,
/// since the timer is its own small piece of state (one active timer or
/// none) with its own display, not a row in that list.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13
/// (mirrors `TimeEntriesViewModel`'s same reasoning).
@MainActor
public final class TimerViewModel: ObservableObject {
    @Published public private(set) var activeTimer: TimeEntry?
    @Published public private(set) var tasks: [PCCTask] = []
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var clients: [PCCClient] = []
    @Published public private(set) var courses: [Course] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let timeEntriesClient: TimeEntriesAPIClient
    private let tasksClient: TasksAPIClient
    private let projectsClient: ProjectsAPIClient
    private let clientsClient: ClientsAPIClient
    private let coursesClient: CoursesAPIClient

    public init(
        timeEntriesClient: TimeEntriesAPIClient,
        tasksClient: TasksAPIClient,
        projectsClient: ProjectsAPIClient,
        clientsClient: ClientsAPIClient,
        coursesClient: CoursesAPIClient
    ) {
        self.timeEntriesClient = timeEntriesClient
        self.tasksClient = tasksClient
        self.projectsClient = projectsClient
        self.clientsClient = clientsClient
        self.coursesClient = coursesClient
    }

    public var isRunning: Bool { activeTimer != nil }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedTimer = timeEntriesClient.getActiveTimer()
            async let loadedTasks = tasksClient.listTasks(projectID: nil, courseID: nil)
            async let loadedProjects = projectsClient.listProjects()
            async let loadedClients = clientsClient.listClients()
            async let loadedCourses = coursesClient.listCourses()
            activeTimer = try await loadedTimer
            tasks = try await loadedTasks
            projects = try await loadedProjects
            clients = try await loadedClients
            courses = try await loadedCourses
        }
    }

    public func start(container: TimeEntryContainer) async {
        await run(verb: "start") {
            activeTimer = try await timeEntriesClient.startTimer(container: container)
        }
    }

    public func stop() async {
        await run(verb: "stop") {
            _ = try await timeEntriesClient.stopTimer()
            activeTimer = nil
        }
    }

    public func cancel() async {
        await run(verb: "cancel") {
            try await timeEntriesClient.cancelTimer()
            activeTimer = nil
        }
    }

    /// Runs a mutation against `activeTimer`, keeping every method's
    /// success/failure handling (clear the error; on failure surface a
    /// message) in one shape instead of four copies — mirrors
    /// `TimeEntriesViewModel.run`.
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) timer: \(error.localizedDescription)"
        }
    }
}
