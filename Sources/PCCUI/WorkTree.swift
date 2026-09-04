import Foundation

/// Which domain object one `WorkNode` stands for — the Work screen's tree
/// is Client → Project → (optional Sprint) → Task (`CONTEXT.md`), plus one
/// synthetic `.unassigned` node holding the Client-less work (issue #89).
///
/// Carries the id rather than the whole model so a node stays cheap to
/// compare and so `WorkViewModel` can look the real object back up when a
/// selection needs to open an edit sheet — the tree is a projection for
/// display, not a second copy of the domain.
public enum WorkNodeKind: Equatable, Sendable {
    case client(UUID)
    /// Everything with no Client above it — Projects with no Client, and
    /// Tasks with no container at all. Synthetic: there is no "Unassigned"
    /// Client row in the database, and nothing can be logged against this
    /// node directly.
    case unassigned
    case project(UUID)
    case sprint(UUID)
    case task(UUID)

    /// The SF Symbol a row of this kind is marked with. On the kind itself
    /// rather than in the view, so a new kind can't be added without
    /// answering what it looks like — the sidebar's own `Screen.systemImage`
    /// (`PCCDesktop/main.swift`) keeps icon and identity together the same
    /// way.
    public var systemImage: String {
        switch self {
        case .client: return "building.2"
        case .unassigned: return "tray"
        case .project: return "folder"
        case .sprint: return "flag"
        case .task: return "checkmark.circle"
        }
    }
}

/// One row of the Work screen's container tree, with its transitive Work
/// Hours total for the selected range already folded in (ADR-0005): a
/// Project's total includes its Tasks' entries, a Client's total includes
/// its Projects' totals.
///
/// A value tree rather than a graph of references: `WorkTree.build` rebuilds
/// the whole thing whenever the data or the range changes, which is cheap at
/// this app's data volumes and means a node can never hold a stale total.
public struct WorkNode: Identifiable, Equatable, Sendable {
    /// Stable across rebuilds — a kind-prefixed id (e.g. `"project:<uuid>"`),
    /// so SwiftUI's `OutlineGroup`/expansion state survives a reload and two
    /// nodes of different kinds can't collide on a shared UUID.
    public let id: String
    public let kind: WorkNodeKind
    public let name: String
    /// `nil` rather than `[]` for a leaf — SwiftUI's `OutlineGroup` draws a
    /// disclosure triangle for any non-`nil` children array, including an
    /// empty one, so a childless node has to say so with `nil`.
    public let children: [WorkNode]?
    /// This node's transitive total in seconds, for the range the tree was
    /// built with. `0` is a real value that stays in the tree — the range
    /// filters the numbers, never membership (issue #89).
    public let totalSeconds: Double

    public init(id: String, kind: WorkNodeKind, name: String, children: [WorkNode]?, totalSeconds: Double) {
        self.id = id
        self.kind = kind
        self.name = name
        self.children = children
        self.totalSeconds = totalSeconds
    }
}

/// Builds the Work screen's tree out of the flat lists the API clients
/// return. Pure and `enum`-namespaced — no state, no networking — so the
/// fold rules (ADR-0005), the "Sprint level only when a Project uses
/// Sprints" rule and the running-timer exclusion are all unit-testable
/// without a view model or a live backend (`WorkTreeTests`).
public enum WorkTree {
    /// The tree for `range`, a half-open `[start, end)` interval.
    ///
    /// Course-owned Projects (`courseID != nil`) and Course-owned Tasks are
    /// excluded outright — they belong to the School dashboard (issue #90),
    /// not here. Every remaining Client, Project, Sprint and Task appears
    /// whether or not it has hours in `range`; only the totals move with the
    /// range.
    public static func build(
        clients: [PCCClient],
        projects: [Project],
        sprints: [Sprint],
        tasks: [PCCTask],
        timeEntries: [TimeEntry],
        range: (start: Date, end: Date)
    ) -> [WorkNode] {
        let workProjects = projects.filter { $0.courseID == nil }
        let workProjectIDs = Set(workProjects.map(\.id))
        let seconds = countableSeconds(timeEntries, range: range)

        // Tasks that belong on this screen: one of a work Project's, or
        // container-less entirely (those hang off "Unassigned" below, so the
        // owner can still see and re-file them — the job the deleted Tasks
        // screen did).
        let workTasks = tasks.filter { task in
            guard task.courseID == nil else { return false }
            guard let projectID = task.projectID else { return true }
            return workProjectIDs.contains(projectID)
        }

        let projectNodes = workProjects.reduce(into: [UUID: WorkNode]()) { nodes, project in
            nodes[project.id] = projectNode(
                project, sprints: sprints, tasks: workTasks, seconds: seconds)
        }

        var roots = clients
            .sorted { $0.name < $1.name }
            .map { client -> WorkNode in
                let children = workProjects
                    .filter { $0.clientID == client.id }
                    .sorted { $0.name < $1.name }
                    .compactMap { projectNodes[$0.id] }
                return WorkNode(
                    id: "client:\(client.id)",
                    kind: .client(client.id),
                    name: client.name,
                    children: children.isEmpty ? nil : children,
                    totalSeconds: seconds[.client(client.id), default: 0]
                        + children.reduce(0) { $0 + $1.totalSeconds }
                )
            }

        let orphanProjects = workProjects
            .filter { $0.clientID == nil }
            .sorted { $0.name < $1.name }
            .compactMap { projectNodes[$0.id] }
        let orphanTasks = workTasks
            .filter { $0.projectID == nil }
            .sorted { $0.title < $1.title }
            .map { taskNode($0, seconds: seconds) }
        let unassignedChildren = orphanProjects + orphanTasks
        if !unassignedChildren.isEmpty {
            roots.append(
                WorkNode(
                    id: "unassigned",
                    kind: .unassigned,
                    name: "Unassigned",
                    children: unassignedChildren,
                    totalSeconds: unassignedChildren.reduce(0) { $0 + $1.totalSeconds }
                )
            )
        }
        return roots
    }

    /// One Project's node. Its children are its Sprints (each holding that
    /// Sprint's Tasks) plus every Task the Project owns outside a Sprint —
    /// a Project with no Sprints at all gets its Tasks as direct children,
    /// never an empty intermediate row (issue #89).
    ///
    /// A Sprint that exists but holds no Tasks *is* still shown, which is
    /// the narrow reading of that rule: the row the rule forbids is a
    /// synthetic level the tree invented over a Project that doesn't use
    /// Sprints, not a real Sprint the owner deliberately created and has to
    /// be able to select, rename, or delete. It reads as a `0m` leaf, the
    /// same way an hours-less Project does.
    private static func projectNode(
        _ project: Project,
        sprints: [Sprint],
        tasks: [PCCTask],
        seconds: [SecondsKey: Double]
    ) -> WorkNode {
        let projectTasks = tasks.filter { $0.projectID == project.id }
        let projectSprints = sprints.filter { $0.projectID == project.id }.sorted { $0.startDate < $1.startDate }
        let sprintNodes = projectSprints.map { sprint -> WorkNode in
            let children = projectTasks
                .filter { $0.sprintID == sprint.id }
                .sorted { $0.title < $1.title }
                .map { taskNode($0, seconds: seconds) }
            return WorkNode(
                id: "sprint:\(sprint.id)",
                kind: .sprint(sprint.id),
                name: sprint.name,
                children: children.isEmpty ? nil : children,
                // A Sprint is a grouping of Tasks, not a Time Entry
                // container (ADR-0004) — it has no direct hours of its own
                // to add to its Tasks'.
                totalSeconds: children.reduce(0) { $0 + $1.totalSeconds }
            )
        }
        let looseTaskNodes = projectTasks
            .filter { $0.sprintID == nil }
            .sorted { $0.title < $1.title }
            .map { taskNode($0, seconds: seconds) }
        let children = sprintNodes + looseTaskNodes
        return WorkNode(
            id: "project:\(project.id)",
            kind: .project(project.id),
            name: project.name,
            children: children.isEmpty ? nil : children,
            totalSeconds: seconds[.project(project.id), default: 0]
                + children.reduce(0) { $0 + $1.totalSeconds }
        )
    }

    /// A Task is always a leaf: it has nothing below it to fold in, so its
    /// total is its own direct entries only (ADR-0005).
    private static func taskNode(_ task: PCCTask, seconds: [SecondsKey: Double]) -> WorkNode {
        WorkNode(
            id: "task:\(task.id)",
            kind: .task(task.id),
            name: task.title,
            children: nil,
            totalSeconds: seconds[.task(task.id), default: 0]
        )
    }

    /// Which container a bucket of counted seconds belongs to. A private
    /// mirror of `TimeEntryContainer` minus `.course`, since Course time
    /// never reaches this screen — kept separate so `build` can key a
    /// dictionary by it without making `TimeEntryContainer` `Hashable` for
    /// this one use.
    private enum SecondsKey: Hashable {
        case task(UUID)
        case project(UUID)
        case client(UUID)
    }

    /// Direct seconds per container for `[start, end)`, mirroring the
    /// backend's own rollup rules exactly
    /// (`WorkHoursController.completedEntries`): only completed entries
    /// count — a running live timer contributes nothing until it's stopped
    /// (`CONTEXT.md`) — and an entry belongs to the range by its `startDate`
    /// alone rather than being split across a boundary it straddles.
    private static func countableSeconds(
        _ timeEntries: [TimeEntry], range: (start: Date, end: Date)
    ) -> [SecondsKey: Double] {
        var totals: [SecondsKey: Double] = [:]
        for entry in timeEntries {
            guard let endDate = entry.endDate else { continue }
            guard entry.startDate >= range.start, entry.startDate < range.end else { continue }
            let key: SecondsKey
            if let taskID = entry.taskID { key = .task(taskID) }
            else if let projectID = entry.projectID { key = .project(projectID) }
            else if let clientID = entry.clientID { key = .client(clientID) }
            else { continue }
            totals[key, default: 0] += endDate.timeIntervalSince(entry.startDate)
        }
        return totals
    }

    /// Depth-first walk of `nodes`, roots first — how the view finds the
    /// selected node again after a rebuild, and how a Time Entry list scopes
    /// itself to "this node and everything under it."
    public static func flattened(_ nodes: [WorkNode]) -> [WorkNode] {
        nodes.flatMap { [$0] + flattened($0.children ?? []) }
    }

    /// The node with `id` anywhere in `nodes`, or `nil` — used to re-resolve
    /// a selection against a freshly rebuilt tree.
    public static func node(withID id: String, in nodes: [WorkNode]) -> WorkNode? {
        flattened(nodes).first { $0.id == id }
    }
}
