import Foundation

/// Holds the merged Work screen's state (issue #89) — the container tree,
/// the selected node, the range the numbers are computed over, and every
/// CRUD call the five screens this replaces used to own between them
/// (Clients, Projects, Tasks, Time Entries, Work Hours).
///
/// Loads the flat lists once and does the rollup locally
/// (`WorkTree.build`) rather than calling `GET /v1/work-hours` per node:
/// that endpoint returns one flat grouping at a time, and this screen needs
/// every level of the tree totalled at once against the same range. The
/// fold rules mirror the backend's (ADR-0005) and are covered by
/// `WorkTreeTests`.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class WorkViewModel: ObservableObject {
    @Published public private(set) var clients: [PCCClient] = []
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var sprints: [Sprint] = []
    @Published public private(set) var tasks: [PCCTask] = []
    @Published public private(set) var timeEntries: [TimeEntry] = []
    @Published public private(set) var courses: [Course] = []
    /// The whole tree, rebuilt whenever the data or `range` changes.
    @Published public private(set) var tree: [WorkNode] = []
    /// Which node the stats and Time Entry list on the right are scoped to —
    /// a `WorkNode.id`, kept as the id rather than the node itself so a
    /// selection survives a rebuild (`WorkTree.node(withID:in:)`).
    @Published public var selectedNodeID: String?
    @Published public var range = WorkDateRange() {
        didSet { if range != oldValue { rebuild() } }
    }
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let clientsClient: ClientsAPIClient
    private let projectsClient: ProjectsAPIClient
    private let sprintsClient: SprintsAPIClient
    private let tasksClient: TasksAPIClient
    private let timeEntriesClient: TimeEntriesAPIClient
    private let coursesClient: CoursesAPIClient

    public init(
        clientsClient: ClientsAPIClient,
        projectsClient: ProjectsAPIClient,
        sprintsClient: SprintsAPIClient,
        tasksClient: TasksAPIClient,
        timeEntriesClient: TimeEntriesAPIClient,
        coursesClient: CoursesAPIClient
    ) {
        self.clientsClient = clientsClient
        self.projectsClient = projectsClient
        self.sprintsClient = sprintsClient
        self.tasksClient = tasksClient
        self.timeEntriesClient = timeEntriesClient
        self.coursesClient = coursesClient
    }

    // MARK: - Loading

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(noun: "Work", verb: "load") {
            async let loadedClients = clientsClient.listClients()
            async let loadedProjects = projectsClient.listProjects()
            async let loadedTasks = tasksClient.listTasks(projectID: nil, courseID: nil)
            async let loadedEntries = timeEntriesClient.listTimeEntries(
                taskID: nil, projectID: nil, clientID: nil, courseID: nil)
            async let loadedCourses = coursesClient.listCourses()
            clients = try await loadedClients
            projects = try await loadedProjects
            tasks = try await loadedTasks
            timeEntries = try await loadedEntries
            courses = try await loadedCourses
            sprints = try await loadSprints(for: projects)
        }
        rebuild()
    }

    /// Every Sprint across every work Project, gathered one request per
    /// Project — `SprintsAPIClient` has no unscoped "list all Sprints" call
    /// (a Sprint has no meaning outside a Project), so the tree's Sprint
    /// level has to fan out. Course-owned Projects are skipped: their
    /// Sprints belong to the School dashboard (issue #90), not this tree.
    private func loadSprints(for projects: [Project]) async throws -> [Sprint] {
        try await withThrowingTaskGroup(of: [Sprint].self) { group in
            for project in projects where project.courseID == nil {
                group.addTask { [sprintsClient] in try await sprintsClient.listSprints(projectID: project.id) }
            }
            var all: [Sprint] = []
            for try await sprints in group {
                all.append(contentsOf: sprints)
            }
            return all
        }
    }

    /// Rebuilds `tree` from the currently-loaded lists and `range`, and
    /// re-resolves `selectedNodeID` — a selected node that no longer exists
    /// (its Project was deleted, say) clears the selection rather than
    /// leaving the right-hand panels scoped to something gone.
    private func rebuild() {
        tree = WorkTree.build(
            clients: clients, projects: projects, sprints: sprints, tasks: tasks,
            timeEntries: timeEntries, range: range.resolved()
        )
        if let id = selectedNodeID, WorkTree.node(withID: id, in: tree) == nil {
            selectedNodeID = nil
        }
    }

    // MARK: - Selection

    /// The selected node, or `nil` when nothing is selected — in which case
    /// the stats panels cover the whole tree.
    public var selectedNode: WorkNode? {
        guard let selectedNodeID else { return nil }
        return WorkTree.node(withID: selectedNodeID, in: tree)
    }

    /// What the stats panels are titled with: the selected node's name, or
    /// "All Work" when the whole tree is in scope.
    public var scopeTitle: String {
        selectedNode?.name ?? "All Work"
    }

    /// The nodes the stats cover — the selection's own subtree, or every
    /// root when nothing is selected.
    private var scopedRoots: [WorkNode] {
        guard let node = selectedNode else { return tree }
        return [node]
    }

    /// The total for the current scope and range, in seconds — the hero
    /// figure. Reads straight off the tree rather than re-summing entries,
    /// so it can't disagree with the row totals beside it.
    public var totalSeconds: Double {
        scopedRoots.reduce(0) { $0 + $1.totalSeconds }
    }

    /// Total divided by the number of days in the range that have actually
    /// *happened*, not by every day the window spans.
    ///
    /// Two deliberate choices here. A day with nothing logged still counts —
    /// "average per day" answers "how much of a typical day goes here," and
    /// an idle day is part of that answer. But a day still in the future
    /// does not: the current week's window runs to Sunday even on a Tuesday
    /// (`WorkDateRange.resolved`, so the bar chart's bars don't shuffle as
    /// the week goes on), and dividing Tuesday's hours by seven would report
    /// an average less than half the real one.
    public var averageSecondsPerDay: Double {
        let today = Calendar.current.startOfDay(for: Date())
        let elapsedDays = range.days().filter { $0 <= today }.count
        guard elapsedDays > 0 else { return 0 }
        return totalSeconds / Double(elapsedDays)
    }

    /// One bar per calendar day in the range, in order — seconds logged
    /// inside the current scope on that day. Dense (a day with nothing
    /// logged is a zero bar), mirroring the backend's own `groupBy: day`
    /// rollup.
    public var dailyTotals: [(day: Date, seconds: Double)] {
        let calendar = Calendar.current
        let scoped = scopedEntries
        var totals: [Date: Double] = [:]
        for entry in scoped {
            guard let endDate = entry.endDate else { continue }
            totals[calendar.startOfDay(for: entry.startDate), default: 0]
                += endDate.timeIntervalSince(entry.startDate)
        }
        return range.days().map { (day: $0, seconds: totals[$0] ?? 0) }
    }

    /// The donut's slices: the selected node's direct children and what each
    /// one contributed, largest first, zero-hour children dropped — a donut
    /// with a slice of nothing in it reads as a rendering bug rather than as
    /// information. Empty for a leaf (a Task has no children to break down).
    public var breakdown: [(name: String, seconds: Double)] {
        let children = selectedNode.map { $0.children ?? [] } ?? tree
        return children
            .filter { $0.totalSeconds > 0 }
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .map { (name: $0.name, seconds: $0.totalSeconds) }
    }

    /// The Time Entries the list below the stats shows: those in range that
    /// belong to the current scope's subtree, newest first. A running timer
    /// is excluded — it contributes to no total until it's stopped
    /// (`CONTEXT.md`) — and surfaces as the toolbar's live chip instead.
    public var scopedEntries: [TimeEntry] {
        let (start, end) = range.resolved()
        let containers = scopedContainers
        return timeEntries
            .filter { entry in
                guard entry.endDate != nil else { return false }
                guard entry.startDate >= start, entry.startDate < end else { return false }
                return containers.contains(entry)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Every Task/Project/Client id in the current scope's subtree — what
    /// `scopedEntries` filters against, so selecting a Client picks up the
    /// entries logged against its Projects and their Tasks too (the same
    /// transitive fold the row totals use, ADR-0005).
    private var scopedContainers: ScopedContainers {
        var containers = ScopedContainers()
        for node in WorkTree.flattened(scopedRoots) {
            switch node.kind {
            case .task(let id): containers.tasks.insert(id)
            case .project(let id): containers.projects.insert(id)
            case .client(let id): containers.clients.insert(id)
            case .sprint, .unassigned: break
            }
        }
        return containers
    }

    /// The three id sets that make up one scope, plus the one question ever
    /// asked of them. One type rather than a bare three-way tuple passed
    /// between two methods — the sets only ever travel together, and the
    /// membership test belongs with them rather than beside them.
    private struct ScopedContainers {
        var tasks: Set<UUID> = []
        var projects: Set<UUID> = []
        var clients: Set<UUID> = []

        /// Whether `entry` was logged anywhere inside this scope. A
        /// Course-attached entry never is — Course time belongs to the
        /// School dashboard (issue #90).
        func contains(_ entry: TimeEntry) -> Bool {
            if let taskID = entry.taskID { return tasks.contains(taskID) }
            if let projectID = entry.projectID { return projects.contains(projectID) }
            if let clientID = entry.clientID { return clients.contains(clientID) }
            return false
        }
    }

    // MARK: - Lookups

    public func client(id: UUID) -> PCCClient? { clients.first { $0.id == id } }
    public func project(id: UUID) -> Project? { projects.first { $0.id == id } }
    public func sprint(id: UUID) -> Sprint? { sprints.first { $0.id == id } }
    public func task(id: UUID) -> PCCTask? { tasks.first { $0.id == id } }

    /// Only the Projects this screen owns — Course-owned ones belong to the
    /// School dashboard, so they never appear in a picker here either.
    public var workProjects: [Project] {
        projects.filter { $0.courseID == nil }
    }

    /// The name of whichever Task/Project/Client/Course an entry is attached
    /// to — what the Time Entry list labels each row with. Falls back to a
    /// placeholder rather than crashing when the referenced item isn't
    /// loaded (e.g. deleted between loads).
    public func containerLabel(for entry: TimeEntry) -> String {
        if let taskID = entry.taskID { return tasks.first { $0.id == taskID }?.title ?? "Unknown Task" }
        if let projectID = entry.projectID { return projects.first { $0.id == projectID }?.name ?? "Unknown Project" }
        if let clientID = entry.clientID { return clients.first { $0.id == clientID }?.name ?? "Unknown Client" }
        if let courseID = entry.courseID { return courses.first { $0.id == courseID }?.name ?? "Unknown Course" }
        return "Unattached"
    }

    // MARK: - Clients

    public func createClient(name: String) async {
        await run(noun: "Client", verb: "create") {
            clients.append(try await clientsClient.createClient(name: name))
            clients.sort { $0.name < $1.name }
        }
    }

    public func updateClient(_ existing: PCCClient, name: String) async {
        await run(noun: "Client", verb: "update") {
            let updated = try await clientsClient.updateClient(id: existing.id, name: name)
            if let index = clients.firstIndex(where: { $0.id == updated.id }) { clients[index] = updated }
        }
    }

    public func deleteClient(_ existing: PCCClient) async {
        await run(noun: "Client", verb: "delete") {
            try await clientsClient.deleteClient(id: existing.id)
            clients.removeAll { $0.id == existing.id }
        }
    }

    // MARK: - Projects

    /// Creates a Project and, if given, attaches its Deadline in a follow-up
    /// call — a Project is always created undated on the backend
    /// (`ProjectController.create`), so a Deadline is a separate write.
    public func createProject(_ values: ProjectFormValues) async {
        await run(noun: "Project", verb: "create") {
            var created = try await projectsClient.createProject(name: values.name)
            if let dueDate = values.dueDate {
                created = try await projectsClient.setProjectDeadline(id: created.id, dueDate: dueDate)
            }
            projects.append(created)
            projects.sort { $0.name < $1.name }
        }
    }

    public func updateProject(_ project: Project, with values: ProjectFormValues) async {
        await run(noun: "Project", verb: "update") {
            var updated = try await projectsClient.updateProject(id: project.id, name: values.name)
            if values.dueDate != project.dueDate {
                updated = try await projectsClient.setProjectDeadline(id: project.id, dueDate: values.dueDate)
            }
            if let index = projects.firstIndex(where: { $0.id == updated.id }) { projects[index] = updated }
        }
    }

    public func deleteProject(_ project: Project) async {
        await run(noun: "Project", verb: "delete") {
            try await projectsClient.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
            sprints.removeAll { $0.projectID == project.id }
        }
    }

    // MARK: - Sprints

    public func createSprint(projectID: UUID, _ values: SprintFormValues) async {
        await run(noun: "Sprint", verb: "create") {
            sprints.append(
                try await sprintsClient.createSprint(
                    projectID: projectID, name: values.name,
                    startDate: values.startDate, endDate: values.endDate))
        }
    }

    public func updateSprint(_ existing: Sprint, with values: SprintFormValues) async {
        await run(noun: "Sprint", verb: "update") {
            let updated = try await sprintsClient.updateSprint(
                id: existing.id, name: values.name, startDate: values.startDate, endDate: values.endDate)
            if let index = sprints.firstIndex(where: { $0.id == updated.id }) { sprints[index] = updated }
        }
    }

    public func deleteSprint(_ existing: Sprint) async {
        await run(noun: "Sprint", verb: "delete") {
            try await sprintsClient.deleteSprint(id: existing.id)
            sprints.removeAll { $0.id == existing.id }
            // The backend un-groups the Sprint's Tasks rather than deleting
            // them; mirror that locally so they reappear directly under the
            // Project instead of hanging off a Sprint that's gone.
            for index in tasks.indices where tasks[index].sprintID == existing.id {
                tasks[index].sprintID = nil
            }
        }
    }

    // MARK: - Tasks

    /// Creates a Task and assigns its Project/Sprint/Deadline/Kind in
    /// follow-up calls — a Task is always created bare on the backend
    /// (`TaskController.create`), so each is a separate write. The Sprint
    /// write comes after the Project one, since the backend rejects a Sprint
    /// from a different Project than the Task's own.
    public func createTask(_ values: TaskFormValues) async {
        await run(noun: "Task", verb: "create") {
            var created = try await tasksClient.createTask(title: values.title, notes: values.notes)
            if let projectID = values.projectID {
                created = try await tasksClient.assignTaskProject(id: created.id, projectID: projectID)
            }
            if let sprintID = values.sprintID {
                created = try await tasksClient.assignTaskSprint(id: created.id, sprintID: sprintID)
            }
            if let dueDate = values.dueDate {
                created = try await tasksClient.setTaskDeadline(id: created.id, dueDate: dueDate)
            }
            if let kind = values.kind {
                created = try await tasksClient.setTaskKind(id: created.id, kind: kind)
            }
            tasks.append(created)
        }
    }

    public func updateTask(_ task: PCCTask, with values: TaskFormValues) async {
        await run(noun: "Task", verb: "update") {
            var updated = try await tasksClient.updateTask(
                id: task.id, title: values.title, notes: values.notes)
            if values.projectID != task.projectID {
                updated = try await tasksClient.assignTaskProject(id: task.id, projectID: values.projectID)
            }
            if values.sprintID != task.sprintID || values.projectID != task.projectID {
                updated = try await tasksClient.assignTaskSprint(id: task.id, sprintID: values.sprintID)
            }
            if values.dueDate != task.dueDate {
                updated = try await tasksClient.setTaskDeadline(id: task.id, dueDate: values.dueDate)
            }
            if values.kind != task.kind {
                updated = try await tasksClient.setTaskKind(id: task.id, kind: values.kind)
            }
            replace(updated)
        }
    }

    public func setTaskCompletion(_ task: PCCTask, isComplete: Bool) async {
        await run(noun: "Task", verb: "update") {
            replace(try await tasksClient.setTaskCompletion(id: task.id, isComplete: isComplete))
        }
    }

    public func deleteTask(_ task: PCCTask) async {
        await run(noun: "Task", verb: "delete") {
            try await tasksClient.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
        }
    }

    private func replace(_ updated: PCCTask) {
        guard let index = tasks.firstIndex(where: { $0.id == updated.id }) else { return }
        tasks[index] = updated
    }

    // MARK: - Time Entries

    public func createTimeEntry(_ values: TimeEntryFormValues) async {
        await run(noun: "Time Entry", verb: "create") {
            timeEntries.append(try await timeEntriesClient.createTimeEntry(values))
        }
    }

    public func updateTimeEntry(_ entry: TimeEntry, with values: TimeEntryFormValues) async {
        await run(noun: "Time Entry", verb: "update") {
            let updated = try await timeEntriesClient.updateTimeEntry(id: entry.id, values: values)
            if let index = timeEntries.firstIndex(where: { $0.id == updated.id }) { timeEntries[index] = updated }
        }
    }

    public func deleteTimeEntry(_ entry: TimeEntry) async {
        await run(noun: "Time Entry", verb: "delete") {
            try await timeEntriesClient.deleteTimeEntry(id: entry.id)
            timeEntries.removeAll { $0.id == entry.id }
        }
    }

    /// Runs a mutation, then rebuilds the tree so every row total reflects
    /// it — the one shape every method above shares, instead of a copy of
    /// the error handling and the rebuild per method.
    ///
    /// Takes a `noun` as well as a `verb`, unlike every other view model's
    /// `run(verb:)` (`CoursesViewModel.run`, say), which can hard-code its
    /// one noun: this one screen mutates five different kinds of thing, so
    /// "Couldn't create Sprint" has to name which.
    private func run(noun: String, verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) \(noun): \(error.localizedDescription)"
        }
        rebuild()
    }
}
