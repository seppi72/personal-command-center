import Foundation

/// Holds the Time Entries screen's state and talks to the backend through a
/// `TimeEntriesAPIClient`, plus `TasksAPIClient`/`ProjectsAPIClient`/
/// `ClientsAPIClient`/`CoursesAPIClient` to populate the container pickers —
/// kept separate from `TimeEntriesView` so the view stays a thin rendering
/// of this state (mirrors `TasksViewModel`'s split, extended to a fourth
/// picker source).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class TimeEntriesViewModel: ObservableObject {
    @Published public private(set) var timeEntries: [TimeEntry] = []
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

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedEntries = timeEntriesClient.listTimeEntries(
                taskID: nil, projectID: nil, clientID: nil, courseID: nil
            )
            async let loadedTasks = tasksClient.listTasks(projectID: nil, courseID: nil)
            async let loadedProjects = projectsClient.listProjects()
            async let loadedClients = clientsClient.listClients()
            async let loadedCourses = coursesClient.listCourses()
            timeEntries = try await loadedEntries
            tasks = try await loadedTasks
            projects = try await loadedProjects
            clients = try await loadedClients
            courses = try await loadedCourses
        }
    }

    public func createTimeEntry(_ values: TimeEntryFormValues) async {
        await run(verb: "create") {
            timeEntries.append(try await timeEntriesClient.createTimeEntry(values))
        }
    }

    public func updateTimeEntry(_ timeEntry: TimeEntry, with values: TimeEntryFormValues) async {
        await run(verb: "update") {
            let updated = try await timeEntriesClient.updateTimeEntry(id: timeEntry.id, values: values)
            if let index = timeEntries.firstIndex(where: { $0.id == updated.id }) {
                timeEntries[index] = updated
            }
        }
    }

    public func deleteTimeEntry(_ timeEntry: TimeEntry) async {
        await run(verb: "delete") {
            try await timeEntriesClient.deleteTimeEntry(id: timeEntry.id)
            timeEntries.removeAll { $0.id == timeEntry.id }
        }
    }

    /// Runs a mutation against `timeEntries`, keeping every method's
    /// success/failure handling (clear the error; on failure surface a
    /// message) in one shape instead of four copies.
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Time Entry: \(error.localizedDescription)"
        }
    }
}
