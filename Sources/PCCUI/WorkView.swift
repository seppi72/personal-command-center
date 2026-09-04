import SwiftUI

/// The merged Work screen (issue #89): everything the five separate
/// Clients/Projects/Tasks/Time Entries/Work Hours screens used to do, on one
/// surface modelled on the Timing app's Stats screen — a container tree down
/// the left, a range stepper across the top, and summary statistics plus the
/// Time Entry list on the right.
///
/// Course-owned work is deliberately absent: a Project or Task belonging to
/// a Course belongs to the School dashboard (issue #90), which gets its own
/// deliberately different layout rather than a second copy of this one.
public struct WorkView: View {
    @ObservedObject private var viewModel: WorkViewModel
    @ObservedObject private var timerViewModel: TimerViewModel

    public init(viewModel: WorkViewModel, timerViewModel: TimerViewModel) {
        self.viewModel = viewModel
        self.timerViewModel = timerViewModel
    }

    public var body: some View {
        WorkContent(viewModel: viewModel, timerViewModel: timerViewModel)
            .screenTheme(.liquidGlass)
    }
}

/// Which sheet the screen currently has open. One `Identifiable` enum rather
/// than one `@State` boolean per sheet — the five sheets are mutually
/// exclusive, and an enum makes that a fact of the type rather than a rule
/// five separate flags have to keep between them.
private enum WorkSheet: Identifiable {
    case newProject
    case editProject(Project)
    case newTask
    case editTask(PCCTask)
    case newClient
    case editClient(PCCClient)
    case newSprint(projectID: UUID)
    case editSprint(Sprint)
    case newTimeEntry
    case editTimeEntry(TimeEntry)

    var id: String {
        switch self {
        case .newProject: return "newProject"
        case .editProject(let project): return "editProject:\(project.id)"
        case .newTask: return "newTask"
        case .editTask(let task): return "editTask:\(task.id)"
        case .newClient: return "newClient"
        case .editClient(let client): return "editClient:\(client.id)"
        case .newSprint(let projectID): return "newSprint:\(projectID)"
        case .editSprint(let sprint): return "editSprint:\(sprint.id)"
        case .newTimeEntry: return "newTimeEntry"
        case .editTimeEntry(let entry): return "editTimeEntry:\(entry.id)"
        }
    }
}

/// The screen's actual content — split out from `WorkView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct WorkContent: View {
    @ObservedObject var viewModel: WorkViewModel
    @ObservedObject var timerViewModel: TimerViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    @State private var sheet: WorkSheet?
    /// Which tree rows are disclosed. Keyed by `WorkNode.id`, which is
    /// stable across rebuilds, so expanding a Client survives a reload or a
    /// range step.
    @State private var expanded: Set<String> = []

    private static let treeWidth: CGFloat = 320

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                treeColumn
                Rectangle()
                    .fill(theme.panelLine(colorScheme))
                    .frame(width: 1)
                statsColumn
            }
            .background(GlassScreenBackground())
            .navigationTitle("Work")
            .toolbar { toolbarContent }
            .task {
                await viewModel.load()
                await timerViewModel.load()
            }
            .refreshable {
                await viewModel.load()
                await timerViewModel.load()
            }
            .sheet(item: $sheet) { sheetContent($0) }
            .errorAlert($viewModel.errorMessage)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            runningTimerChip
        }
        ToolbarItem {
            Button {
                startOrStopTimer()
            } label: {
                Label(
                    timerViewModel.isRunning ? "Stop Timer" : "Start Timer",
                    systemImage: timerViewModel.isRunning ? "stop.circle" : "play.circle")
            }
            .disabled(!timerViewModel.isRunning && timerContainer == nil)
        }
        // Discarding a running timer outright, rather than stopping it into
        // a Time Entry — the one timer control the deleted `TimeEntriesView`
        // had that Start/Stop doesn't cover. Shown only while one is
        // running, since there's nothing to cancel otherwise.
        if timerViewModel.isRunning {
            ToolbarItem {
                Button(role: .destructive) {
                    Task { await timerViewModel.cancel() }
                } label: {
                    Label("Cancel Timer", systemImage: "xmark.circle")
                }
            }
        }
        ToolbarItem {
            Button { sheet = .newTimeEntry } label: {
                Label("New Time Entry", systemImage: "stopwatch")
            }
        }
        ToolbarItem {
            Button { sheet = .newTask } label: {
                Label("New Task", systemImage: "checkmark.circle")
            }
        }
        ToolbarItem {
            Menu {
                Button("New Project") { sheet = .newProject }
                Button("New Client") { sheet = .newClient }
                if case .project(let id) = viewModel.selectedNode?.kind {
                    Button("New Sprint") { sheet = .newSprint(projectID: id) }
                }
            } label: {
                Label("New Project", systemImage: "folder.badge.plus")
            }
        }
    }

    /// The live timer, surfaced as a ticking chip rather than folded into
    /// any row's total: a running entry contributes nothing to Work Hours
    /// until it's stopped (`CONTEXT.md`), so showing it in the tree would
    /// contradict every number beside it.
    @ViewBuilder
    private var runningTimerChip: some View {
        if let active = timerViewModel.activeTimer {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    StatusDot(.active)
                    Text(viewModel.containerLabel(for: active))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(PCCDuration.elapsed(context.date.timeIntervalSince(active.startDate)))
                        .font(.pccReadout(13))
                        .foregroundStyle(theme.accent(colorScheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassBubble(.gridCell)
            }
        }
    }

    /// Which container the toolbar's Start Timer would attach to: whatever
    /// the tree has selected, when that selection is something a Time Entry
    /// can actually attach to (ADR-0004). A Sprint or the synthetic
    /// "Unassigned" row isn't one, so the button stays disabled there rather
    /// than silently timing against the parent.
    private var timerContainer: TimeEntryContainer? {
        switch viewModel.selectedNode?.kind {
        case .task(let id): return .task(id)
        case .project(let id): return .project(id)
        case .client(let id): return .client(id)
        case .sprint, .unassigned, .none: return nil
        }
    }

    private func startOrStopTimer() {
        Task {
            if timerViewModel.isRunning {
                await timerViewModel.stop()
                // The stopped entry only becomes Work Hours once it has an
                // end date, so the totals need re-reading, not just the tree
                // rebuilt from what's already loaded.
                await viewModel.load()
            } else if let container = timerContainer {
                await timerViewModel.start(container: container)
            }
        }
    }

    // MARK: - Tree

    private var treeColumn: some View {
        VStack(spacing: 0) {
            if viewModel.tree.isEmpty && !viewModel.isLoading {
                emptyTree
            } else {
                List(selection: $viewModel.selectedNodeID) {
                    ForEach(visibleRows, id: \.node.id) { row in
                        treeRow(row.node, depth: row.depth)
                            .tag(row.node.id)
                    }
                    .panelRows()
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: Self.treeWidth)
    }

    /// The tree flattened to the rows currently on screen, each with the
    /// depth to indent it by — every node whose ancestors are all disclosed.
    ///
    /// Flattened here rather than rendered by a recursive `@ViewBuilder`:
    /// a view function that returns a `ForEach` of itself defines its own
    /// opaque return type in terms of itself, which doesn't compile. Not
    /// `OutlineGroup` either, so a row can carry its own total, its own
    /// context menu and an indent that lines up with the disclosure
    /// triangle.
    private var visibleRows: [(node: WorkNode, depth: Int)] {
        func rows(_ nodes: [WorkNode], depth: Int) -> [(node: WorkNode, depth: Int)] {
            nodes.flatMap { node -> [(node: WorkNode, depth: Int)] in
                guard expanded.contains(node.id), let children = node.children else {
                    return [(node, depth)]
                }
                return [(node, depth)] + rows(children, depth: depth + 1)
            }
        }
        return rows(viewModel.tree, depth: 0)
    }

    private func treeRow(_ node: WorkNode, depth: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
            } label: {
                Image(systemName: expanded.contains(node.id) ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    .opacity(node.children == nil ? 0 : 1)
            }
            .buttonStyle(.plain)
            .disabled(node.children == nil)
            Image(systemName: node.kind.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(node.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            // A row with nothing in range still shows a total, muted rather
            // than hidden — the range filters the numbers, never tree
            // membership (issue #89).
            Text(PCCDuration.compact(node.totalSeconds))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(node.totalSeconds > 0 ? theme.accent(colorScheme) : Color.secondary)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .contentShape(Rectangle())
        .contextMenu { contextMenu(for: node) }
    }

    @ViewBuilder
    private func contextMenu(for node: WorkNode) -> some View {
        switch node.kind {
        case .client(let id):
            if let client = viewModel.client(id: id) {
                Button("Edit Client") { sheet = .editClient(client) }
                Button("Delete Client", role: .destructive) {
                    Task { await viewModel.deleteClient(client) }
                }
            }
        case .project(let id):
            if let project = viewModel.project(id: id) {
                Button("Edit Project") { sheet = .editProject(project) }
                Button("New Sprint") { sheet = .newSprint(projectID: id) }
                Button("Delete Project", role: .destructive) {
                    Task { await viewModel.deleteProject(project) }
                }
            }
        case .sprint(let id):
            if let sprint = viewModel.sprint(id: id) {
                Button("Edit Sprint") { sheet = .editSprint(sprint) }
                Button("Delete Sprint", role: .destructive) {
                    Task { await viewModel.deleteSprint(sprint) }
                }
            }
        case .task(let id):
            if let task = viewModel.task(id: id) {
                Button("Edit Task") { sheet = .editTask(task) }
                Button(task.isComplete ? "Mark Incomplete" : "Mark Complete") {
                    Task { await viewModel.setTaskCompletion(task, isComplete: !task.isComplete) }
                }
                Button("Delete Task", role: .destructive) {
                    Task { await viewModel.deleteTask(task) }
                }
            }
        case .unassigned:
            EmptyView()
        }
    }

    /// The whole-screen empty state: one call to action, since with no
    /// Projects there is nothing to select, total, or log time against
    /// either.
    private var emptyTree: some View {
        VStack(spacing: 10) {
            Text("No Work Yet")
                .font(.headline)
            Text("Create a Project to start tracking work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Project") { sheet = .newProject }
                .buttonStyle(.borderedProminent)
        }
        .padding(PCCChassis.outerMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stats

    private var statsColumn: some View {
        VStack(spacing: 0) {
            rangeStepper
                .padding(.horizontal, PCCChassis.outerMargin)
                .padding(.top, PCCChassis.outerMargin)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryBubble
                    dayChartBubble
                    breakdownBubble
                    entryList
                }
                .padding(.horizontal, PCCChassis.outerMargin)
                .padding(.bottom, PCCChassis.outerMargin)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Today / Week / Month with previous-next arrows. Stepping changes only
    /// which numbers the panels show — the tree keeps every row either way.
    private var rangeStepper: some View {
        HStack(spacing: 10) {
            Picker("", selection: $viewModel.range.unit) {
                ForEach(WorkRangeUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            Button { viewModel.range.step(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.pccControlChip)
            Text(viewModel.range.title())
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 130)
            Button { viewModel.range.step(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.pccControlChip)
            Spacer()
        }
    }

    /// Total and average-per-day for the current scope. Renders zeroed
    /// rather than hidden when there's nothing logged, so the layout doesn't
    /// jump once data arrives.
    private var summaryBubble: some View {
        HStack(alignment: .top, spacing: 32) {
            statFigure("Total", seconds: viewModel.totalSeconds)
            statFigure("Average Per Day", seconds: viewModel.averageSecondsPerDay)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.scopeTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if viewModel.selectedNodeID != nil {
                    Button("Clear Selection") { viewModel.selectedNodeID = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
    }

    private func statFigure(_ label: String, seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Text(PCCDuration.stamp(seconds))
                .font(.pccReadout(24))
                .foregroundStyle(theme.accent(colorScheme))
        }
    }

    /// One bar per day in the range, heights relative to the range's own
    /// busiest day — an absolute scale would flatten a quiet week into
    /// nothing.
    private var dayChartBubble: some View {
        let totals = viewModel.dailyTotals
        let peak = totals.map(\.seconds).max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("By Day")
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(totals, id: \.day) { entry in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(entry.seconds > 0 ? theme.accent(colorScheme) : theme.panelLine(colorScheme))
                            .frame(height: max(2, peak > 0 ? 90 * entry.seconds / peak : 2))
                        Text(Self.dayLabel(entry.day))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112, alignment: .bottom)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
    }

    /// Time by child container of the selected node, as a donut — the
    /// "where did this Client's hours actually go" read the tree's own
    /// column of totals makes you compare row by row.
    private var breakdownBubble: some View {
        let slices = viewModel.breakdown
        let total = slices.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 12) {
            Text("By \(viewModel.selectedNodeID == nil ? "Client" : "Child")")
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            if slices.isEmpty {
                Text("Nothing logged in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 120, alignment: .center)
            } else {
                HStack(spacing: 24) {
                    donut(slices: slices, total: total)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(slices.prefix(6).enumerated()), id: \.offset) { index, slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Self.sliceColor(index, theme: theme, colorScheme: colorScheme))
                                    .frame(width: 8, height: 8)
                                Text(slice.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(PCCDuration.compact(slice.seconds))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
    }

    private func donut(slices: [(name: String, seconds: Double)], total: Double) -> some View {
        Canvas { context, size in
            guard total > 0 else { return }
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
            var start = Angle.degrees(-90)
            for (index, slice) in slices.enumerated() {
                let sweep = Angle.degrees(360 * slice.seconds / total)
                var path = Path()
                path.move(to: CGPoint(x: rect.midX, y: rect.midY))
                path.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                    startAngle: start, endAngle: start + sweep, clockwise: false)
                path.closeSubpath()
                context.fill(path, with: .color(Self.sliceColor(index, theme: theme, colorScheme: colorScheme)))
                start += sweep
            }
            // Punched out rather than drawn as a stroked ring, so the hole
            // reads as the bubble's own glass showing through.
            context.blendMode = .destinationOut
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: rect.width / 4, dy: rect.height / 4)), with: .color(.black))
        }
    }

    /// Slice colors: the theme's accent stepped through decreasing opacity
    /// rather than a rainbow — a breakdown of one quantity is one hue at
    /// different weights, not six unrelated categories.
    private static func sliceColor(_ index: Int, theme: ScreenTheme, colorScheme: ColorScheme) -> Color {
        theme.accent(colorScheme).opacity(max(0.25, 1 - Double(index) * 0.15))
    }

    // MARK: - Time Entries

    private var entryList: some View {
        let entries = viewModel.scopedEntries
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Time Entries")
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if entries.isEmpty {
                Text("No Time Entries in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            }
        }
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.containerLabel(for: entry))
                    .font(.system(size: 14, weight: .semibold))
                Text(Self.entrySubtitle(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(PCCDuration.stamp((entry.endDate ?? entry.startDate).timeIntervalSince(entry.startDate)))
                .font(.pccReadout(14))
                .foregroundStyle(theme.accent(colorScheme))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
        .contextMenu {
            Button("Edit Time Entry") { sheet = .editTimeEntry(entry) }
            Button("Delete Time Entry", role: .destructive) {
                Task { await viewModel.deleteTimeEntry(entry) }
            }
        }
    }

    private static func entrySubtitle(_ entry: TimeEntry) -> String {
        let span = "\(timeFormatter.string(from: entry.startDate))–\(entry.endDate.map { timeFormatter.string(from: $0) } ?? "running")"
        let day = dayFormatter.string(from: entry.startDate)
        guard let notes = entry.notes, !notes.isEmpty else { return "\(day)   ·   \(span)" }
        return "\(day)   ·   \(span)   ·   \(notes)"
    }

    private static func dayLabel(_ day: Date) -> String {
        barDayFormatter.string(from: day)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let barDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: WorkSheet) -> some View {
        switch sheet {
        case .newProject:
            ProjectFormSheet(title: "New Project", initialName: "", initialDueDate: nil) { values in
                await viewModel.createProject(values)
            }
        case .editProject(let project):
            ProjectFormSheet(
                title: "Edit Project", initialName: project.name, initialDueDate: project.dueDate
            ) { values in
                await viewModel.updateProject(project, with: values)
            }
        case .newClient:
            ClientFormSheet(title: "New Client", initialName: "") { name in
                await viewModel.createClient(name: name)
            }
        case .editClient(let client):
            ClientFormSheet(title: "Edit Client", initialName: client.name) { name in
                await viewModel.updateClient(client, name: name)
            }
        case .newSprint(let projectID):
            SprintFormSheet(
                title: "New Sprint", initialName: "", initialStartDate: Date(),
                initialEndDate: Date().addingTimeInterval(14 * 24 * 3600)
            ) { values in
                await viewModel.createSprint(projectID: projectID, values)
            }
        case .editSprint(let sprint):
            SprintFormSheet(
                title: "Edit Sprint", initialName: sprint.name,
                initialStartDate: sprint.startDate, initialEndDate: sprint.endDate
            ) { values in
                await viewModel.updateSprint(sprint, with: values)
            }
        case .newTask:
            TaskFormSheet(
                title: "New Task", initialTitle: "", initialNotes: "",
                initialProjectID: defaultTaskProjectID, initialCourseID: nil,
                initialSprintID: defaultTaskSprintID, initialDueDate: nil,
                projects: viewModel.workProjects, courses: [], sprints: viewModel.sprints
            ) { values in
                await viewModel.createTask(values)
            }
        case .editTask(let task):
            TaskFormSheet(
                title: "Edit Task", initialTitle: task.title, initialNotes: task.notes ?? "",
                initialProjectID: task.projectID, initialCourseID: task.courseID,
                initialSprintID: task.sprintID, initialKind: task.kind, initialDueDate: task.dueDate,
                projects: viewModel.workProjects, courses: [], sprints: viewModel.sprints
            ) { values in
                await viewModel.updateTask(task, with: values)
            }
        case .newTimeEntry:
            TimeEntryFormSheet(
                title: "New Time Entry", initialValues: defaultTimeEntryValues,
                tasks: viewModel.tasks, projects: viewModel.workProjects,
                clients: viewModel.clients, courses: viewModel.courses
            ) { values in
                await viewModel.createTimeEntry(values)
            }
        case .editTimeEntry(let entry):
            TimeEntryFormSheet(
                title: "Edit Time Entry",
                initialValues: TimeEntryFormValues(
                    startDate: entry.startDate, endDate: entry.endDate ?? Date(), notes: entry.notes,
                    taskID: entry.taskID, projectID: entry.projectID,
                    clientID: entry.clientID, courseID: entry.courseID),
                tasks: viewModel.tasks, projects: viewModel.workProjects,
                clients: viewModel.clients, courses: viewModel.courses
            ) { values in
                await viewModel.updateTimeEntry(entry, with: values)
            }
        }
    }

    /// A new Task pre-fills the Project the tree has selected — creating one
    /// while looking at a Project almost always means creating it *there*,
    /// and the picker is still free to disagree.
    private var defaultTaskProjectID: UUID? {
        switch viewModel.selectedNode?.kind {
        case .project(let id): return id
        case .sprint(let id): return viewModel.sprint(id: id)?.projectID
        case .task(let id): return viewModel.task(id: id)?.projectID
        case .client, .unassigned, .none: return nil
        }
    }

    private var defaultTaskSprintID: UUID? {
        if case .sprint(let id) = viewModel.selectedNode?.kind { return id }
        return nil
    }

    /// A new Time Entry pre-fills the selected container the same way, and
    /// starts inside the range being looked at rather than at "now" — a
    /// backfilled entry belongs to the window on screen.
    private var defaultTimeEntryValues: TimeEntryFormValues {
        let (start, end) = viewModel.range.resolved()
        let base = min(max(Date(), start), end)
        var values = TimeEntryFormValues(startDate: base, endDate: base.addingTimeInterval(3600))
        switch timerContainer {
        case .task(let id): values.taskID = id
        case .project(let id): values.projectID = id
        case .client(let id): values.clientID = id
        case .course(let id): values.courseID = id
        case .none: break
        }
        return values
    }
}
