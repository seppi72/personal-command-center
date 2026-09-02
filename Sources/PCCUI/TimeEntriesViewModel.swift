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

    /// `timeEntries` bucketed by whichever single Task/Project/Client/Course
    /// each one is attached to (ADR-0004) and totaled — the Punch Clock
    /// screen's own reason for existing: "how many hours for each Task"
    /// rather than a flat log of individual entries. Sorted by total
    /// duration, most-logged first, so the roster doubles as a quick
    /// leaderboard of where time actually went. Recomputed on every access
    /// rather than cached, since it's cheap for the data volumes this app
    /// deals in and staying correct after any mutation matters more than
    /// the cost of re-bucketing.
    public var groupedTimeEntries: [TimeEntryGroup] {
        var order: [String] = []
        var entriesByKey: [String: [TimeEntry]] = [:]
        var labelByKey: [String: String] = [:]
        for entry in timeEntries {
            let key = containerKey(for: entry)
            if entriesByKey[key] == nil {
                order.append(key)
                labelByKey[key] = containerLabel(for: entry)
            }
            entriesByKey[key, default: []].append(entry)
        }
        return order
            .map { TimeEntryGroup(id: $0, label: labelByKey[$0] ?? $0, entries: entriesByKey[$0] ?? []) }
            .sorted { $0.totalDuration > $1.totalDuration }
    }

    private func containerKey(for entry: TimeEntry) -> String {
        if let taskID = entry.taskID { return "task:\(taskID)" }
        if let projectID = entry.projectID { return "project:\(projectID)" }
        if let clientID = entry.clientID { return "client:\(clientID)" }
        if let courseID = entry.courseID { return "course:\(courseID)" }
        return "unattached"
    }

    /// The name of whichever Task/Project/Client/Course `entry` is attached
    /// to, looked up from the already-loaded picker lists — falls back to a
    /// placeholder rather than crashing if the referenced item isn't in
    /// those lists (e.g. deleted between loads). Public, not just an
    /// internal helper for `groupedTimeEntries`, since `TimeEntriesView`
    /// also renders it directly for the New/Edit Time Entry flow.
    public func containerLabel(for entry: TimeEntry) -> String {
        if let taskID = entry.taskID {
            return tasks.first { $0.id == taskID }?.title ?? "Unknown Task"
        }
        if let projectID = entry.projectID {
            return projects.first { $0.id == projectID }?.name ?? "Unknown Project"
        }
        if let clientID = entry.clientID {
            return clients.first { $0.id == clientID }?.name ?? "Unknown Client"
        }
        if let courseID = entry.courseID {
            return courses.first { $0.id == courseID }?.name ?? "Unknown Course"
        }
        return "Unattached"
    }

    /// "1H 32M" past an hour, "37M" until then — the compact duration-stamp
    /// format `TimeEntriesView`'s group roster, individual entry rows, and
    /// both status strips all share. Moved here from a free function in
    /// `TimeEntriesView.swift` (issue #70) so it's covered by a unit test at
    /// this type's existing pure-logic seam (`TimeEntriesViewModelTests`,
    /// mirroring `TasksViewModel.isOverdue`) rather than only exercised by
    /// eye. `static nonisolated` rather than an instance method: it closes
    /// over nothing but its argument, and marking it `nonisolated` lets a
    /// test call it without hopping onto the main actor the way every other
    /// member of this `@MainActor` class requires. Distinct from
    /// `TimeEntriesContent.formattedElapsed(_:)`, the hero's own
    /// ":"-separated ticking readout — that one stays a view-local concern,
    /// per its own doc comment.
    public static nonisolated func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)H \(String(format: "%02d", minutes))M"
        }
        return "\(minutes)M"
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

/// One container's worth of Time Entries, bucketed together by
/// `TimeEntriesViewModel.groupedTimeEntries` — `id` is an opaque grouping
/// key (e.g. `"task:<uuid>"`), not a domain identifier of its own.
public struct TimeEntryGroup: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let entries: [TimeEntry]

    /// The sum of every entry's own span — a running entry (`endDate ==
    /// nil`) counts through "now" rather than being excluded, so a group
    /// with an active timer keeps growing as time passes, not just once
    /// the timer stops.
    public var totalDuration: TimeInterval {
        entries.reduce(0) { $0 + ($1.endDate ?? Date()).timeIntervalSince($1.startDate) }
    }

    public var containsRunning: Bool {
        entries.contains(where: \.isRunning)
    }
}
