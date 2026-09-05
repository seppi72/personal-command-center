import SwiftUI

/// The merged Work screen (issue #89): everything the five separate
/// Clients/Projects/Tasks/Time Entries/Work Hours screens used to do, on one
/// surface — laid out as a dashboard rather than the earlier tree-and-stats
/// split, with the container tree kept as one card among the panels instead
/// of as a permanent left column.
///
/// The dashboard reads top-down as "how much, over what, on what": four
/// figures across the top, the week's shape and the live timer under them,
/// then the tree and the two breakdowns, then the Time Entries themselves.
/// Every panel is scoped by the same tree selection and the same range
/// stepper, so the whole screen answers one question at a time.
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
    /// The tracker's Client → Project → Sprint → Task cascade. Each level
    /// narrows the one below it; see `TimeTrackerCard` for why the Sprint
    /// level filters rather than being startable itself.
    @State private var picked = TrackerSelection()

    /// The right-hand column's width — the tracker, the ring and the donut
    /// all share it, so the dashboard reads as two columns rather than four
    /// panels of four widths.
    private static let sideColumnWidth: CGFloat = 320

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statStrip
                    activityRow
                    breakdownRow
                    entryList
                }
                .padding(PCCChassis.outerMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(GlassScreenBackground())
            .navigationTitle("Work")
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

    // MARK: - Header

    /// Title, one line of orientation, the range stepper, and the two
    /// things this screen is opened to create. The actions live here rather
    /// than in the window toolbar so the screen's own controls read as part
    /// of the dashboard, the way its range stepper always has.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work")
                        .font(.system(size: 30, weight: .bold))
                    Text("Track clients, projects, and where the hours went.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                Button {
                    sheet = .newTask
                } label: {
                    Label("New Task", systemImage: "checkmark.circle")
                }
                .buttonStyle(.pccControlChip)
                Menu {
                    Button("New Project") { sheet = .newProject }
                    Button("New Client") { sheet = .newClient }
                    if case .project(let id) = viewModel.selectedNode?.kind {
                        Button("New Sprint") { sheet = .newSprint(projectID: id) }
                    }
                    Divider()
                    Button("New Time Entry") { sheet = .newTimeEntry }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .pccBorderlessMenu()
                .fixedSize()
            }
            rangeStepper
        }
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
            Spacer(minLength: 0)
            scopeChip
        }
    }

    /// What every figure on the screen is currently scoped to, and the way
    /// back out of it. Sits with the range stepper because the two together
    /// are the whole filter: this much time, this part of the tree.
    @ViewBuilder
    private var scopeChip: some View {
        if viewModel.selectedNodeID != nil {
            Button {
                viewModel.selectedNodeID = nil
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.scopeTitle)
                        .lineLimit(1)
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
            }
            .buttonStyle(.pccControlChip)
        } else {
            Text("All Work")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stat strip

    /// The four figures the screen opens on. Hours logged is the hero —
    /// filled in the accent rather than left as glass, since it's the one
    /// number the screen exists to report; the other three are the context
    /// that makes it mean something.
    private var statStrip: some View {
        let completion = viewModel.taskCompletion
        return HStack(spacing: 14) {
            heroTile
            statTile(
                "Average Per Day", value: PCCDuration.stamp(viewModel.averageSecondsPerDay),
                caption: viewModel.range.unit.title)
            statTile(
                "Projects", value: "\(viewModel.scopedProjectCount)",
                caption: "in scope")
            statTile(
                "Tasks Open", value: "\(viewModel.openTaskCount)",
                caption: "\(completion.complete) of \(completion.total) done")
        }
    }

    private var heroTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hours Logged")
                .pccPanelLabel()
                .foregroundStyle(.white.opacity(0.85))
            Text(PCCDuration.stamp(viewModel.totalSeconds))
                .font(.pccReadout(30))
                .foregroundStyle(.white)
            Text(viewModel.range.title())
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GlassBubbleStyle.gridCell.cornerRadius, style: .continuous)
                .fill(theme.accent(colorScheme))
        )
    }

    private func statTile(_ label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Text(value)
                .font(.pccReadout(30))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble(.gridCell)
    }

    // MARK: - Activity + tracker

    private var activityRow: some View {
        HStack(alignment: .top, spacing: 14) {
            dayChartBubble
            TimeTrackerCard(
                viewModel: viewModel, timerViewModel: timerViewModel, picked: $picked,
                onStopped: { await viewModel.load() }
            )
            .frame(width: Self.sideColumnWidth)
        }
    }

    /// One bar per day in the range, heights relative to the range's own
    /// busiest day — an absolute scale would flatten a quiet week into
    /// nothing. The busiest day is the only one drawn at full accent, so the
    /// chart says which day carried the range without a label per bar.
    private var dayChartBubble: some View {
        let totals = viewModel.dailyTotals
        let peak = totals.map(\.seconds).max() ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("By Day")
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
                Spacer()
                if peak > 0 {
                    Text("Busiest \(PCCDuration.compact(peak))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(totals, id: \.day) { entry in
                    dayBar(entry, peak: peak)
                }
            }
            .frame(height: 150, alignment: .bottom)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
    }

    private func dayBar(_ entry: (day: Date, seconds: Double), peak: Double) -> some View {
        let isPeak = peak > 0 && entry.seconds == peak
        let height = peak > 0 ? 118 * entry.seconds / peak : 0
        return VStack(spacing: 8) {
            Capsule(style: .continuous)
                .fill(barFill(isPeak: isPeak, hasHours: entry.seconds > 0))
                .frame(height: max(6, height))
            Text(Self.dayLabel(entry.day))
                .font(.system(size: 10))
                .foregroundStyle(isPeak ? theme.accent(colorScheme) : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func barFill(isPeak: Bool, hasHours: Bool) -> Color {
        guard hasHours else { return theme.panelLine(colorScheme) }
        return theme.accent(colorScheme).opacity(isPeak ? 1 : 0.42)
    }

    // MARK: - Tree + breakdowns

    private var breakdownRow: some View {
        HStack(alignment: .top, spacing: 14) {
            treeBubble
            VStack(spacing: 14) {
                completionBubble
                breakdownBubble
            }
            .frame(width: Self.sideColumnWidth)
        }
    }

    /// Client → Project → Sprint → Task, each row carrying its own
    /// transitive total for the range, and selecting one scopes every other
    /// panel to it. Hand-rolled rows rather than a `List`, so the tree can
    /// sit in a card on the dashboard instead of owning a column.
    private var treeBubble: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clients and Projects")
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("New Project") { sheet = .newProject }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent(colorScheme))
            }
            if viewModel.tree.isEmpty {
                emptyTree
            } else {
                VStack(spacing: 2) {
                    ForEach(visibleRows, id: \.node.id) { row in
                        treeRow(row.node, depth: row.depth)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
    }

    /// The tree flattened to the rows currently on screen, each with the
    /// depth to indent it by — every node whose ancestors are all disclosed.
    ///
    /// Flattened here rather than rendered by a recursive `@ViewBuilder`:
    /// a view function that returns a `ForEach` of itself defines its own
    /// opaque return type in terms of itself, which doesn't compile.
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
        let isSelected = viewModel.selectedNodeID == node.id
        return HStack(spacing: 6) {
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
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowHighlight(isSelected))
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedNodeID = isSelected ? nil : node.id
        }
        .contextMenu { contextMenu(for: node) }
    }

    private func rowHighlight(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: PCCChassis.controlCornerRadius, style: .continuous)
            .fill(isSelected ? theme.accent(colorScheme).opacity(0.14) : .clear)
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

    /// The empty state: one call to action, since with no Projects there is
    /// nothing to select, total, or log time against either.
    private var emptyTree: some View {
        VStack(spacing: 10) {
            Text("No work yet")
                .font(.headline)
            Text("Create a Project to start tracking work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Project") { sheet = .newProject }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    /// Tasks done over Tasks in scope, as a ring. Counts Tasks rather than
    /// hours on purpose: the hours are already three panels on this screen,
    /// and "how far through the work am I" is the question none of them
    /// answer.
    private var completionBubble: some View {
        let completion = viewModel.taskCompletion
        let fraction = completion.total > 0 ? Double(completion.complete) / Double(completion.total) : 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("Task Progress")
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                completionRing(fraction)
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    if completion.total == 0 {
                        Text("No Tasks in scope.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(completion.complete) done")
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(completion.total - completion.complete) still open")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
    }

    private func completionRing(_ fraction: Double) -> some View {
        ZStack {
            Circle()
                .stroke(theme.panelLine(colorScheme), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(
                    theme.accent(colorScheme),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.pccReadout(17))
        }
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
                    .frame(height: 96, alignment: .center)
            } else {
                HStack(spacing: 18) {
                    donut(slices: slices, total: total)
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(slices.prefix(5).enumerated()), id: \.offset) { index, slice in
                            sliceRow(index: index, slice: slice)
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

    private func sliceRow(index: Int, slice: (name: String, seconds: Double)) -> some View {
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

    /// A new Time Entry pre-fills whatever the tracker's cascade currently
    /// points at, and starts inside the range being looked at rather than at
    /// "now" — a backfilled entry belongs to the window on screen.
    private var defaultTimeEntryValues: TimeEntryFormValues {
        let (start, end) = viewModel.range.resolved()
        let base = min(max(Date(), start), end)
        var values = TimeEntryFormValues(startDate: base, endDate: base.addingTimeInterval(3600))
        switch picked.container {
        case .task(let id): values.taskID = id
        case .project(let id): values.projectID = id
        case .client(let id): values.clientID = id
        case .course(let id): values.courseID = id
        case .none: break
        }
        return values
    }
}

extension View {
    /// `.menuStyle(.borderlessButton)` on macOS, where a `Menu`'s default
    /// pulldown chrome would fight the custom trigger label under it, and a
    /// no-op on iOS, where that style doesn't exist. Mirrors the same
    /// `#if os(macOS)` guard `PCCMenuPicker` already carries.
    fileprivate func pccBorderlessMenu() -> some View {
        #if os(macOS)
        return menuStyle(.borderlessButton)
        #else
        return self
        #endif
    }
}

// MARK: - Time tracker

/// The tracker's cascade: which Client, Project, Sprint and Task are picked.
/// One value rather than four loose `@State` ids, so "picking a Client
/// clears the Project under it" is a rule of the type instead of four
/// `onChange` handlers that have to agree.
private struct TrackerSelection: Equatable {
    var clientID: UUID?
    var projectID: UUID?
    var sprintID: UUID?
    var taskID: UUID?

    /// What a timer started right now would attach to: the deepest level
    /// picked that a Time Entry can actually hold (ADR-0004). A Sprint is a
    /// grouping of Tasks, not a container, so it never appears here — it
    /// narrows the Task list above and nothing else.
    var container: TimeEntryContainer? {
        if let taskID { return .task(taskID) }
        if let projectID { return .project(projectID) }
        if let clientID { return .client(clientID) }
        return nil
    }

    mutating func setClient(_ id: UUID?) {
        clientID = id
        projectID = nil
        sprintID = nil
        taskID = nil
    }

    mutating func setProject(_ id: UUID?) {
        projectID = id
        sprintID = nil
        taskID = nil
    }

    mutating func setSprint(_ id: UUID?) {
        sprintID = id
        taskID = nil
    }
}

/// The dashboard's hero control: pick Client → Project → Sprint → Task, then
/// start the clock against it. Filled in the accent like the hours tile,
/// since a running timer is the one thing on this screen that is happening
/// rather than being reported.
///
/// The cascade is deliberately loose at every level — stopping at a Client
/// and starting logs against the Client, which is exactly what ADR-0004's
/// direct Client attachment is for (a call, admin time, anything not
/// task-shaped). Only the Sprint level can't be started against, because a
/// Sprint isn't a Time Entry container at all.
private struct TimeTrackerCard: View {
    @ObservedObject var viewModel: WorkViewModel
    @ObservedObject var timerViewModel: TimerViewModel
    @Binding var picked: TrackerSelection
    /// Called after a timer stops, so the screen can re-read its totals —
    /// a stopped entry only becomes Work Hours once it has an end date.
    let onStopped: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            readout
            if timerViewModel.isRunning {
                runningLabel
            } else {
                cascade
            }
            controls
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GlassBubbleStyle.gridCell.cornerRadius, style: .continuous)
                .fill(theme.accent(colorScheme))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Time Tracker")
                .pccPanelLabel()
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .opacity(timerViewModel.isRunning ? 1 : 0.35)
        }
    }

    /// Ticks every second while running, and rests at zero otherwise — a
    /// dash or an empty space would make the card jump the moment it starts.
    @ViewBuilder
    private var readout: some View {
        if let active = timerViewModel.activeTimer {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(PCCDuration.elapsed(context.date.timeIntervalSince(active.startDate)))
                    .font(.pccReadout(34))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        } else {
            Text("00:00")
                .font(.pccReadout(34))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var runningLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timerViewModel.activeTimer.map { viewModel.containerLabel(for: $0) } ?? "")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("Started \(startedAt)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startedAt: String {
        guard let active = timerViewModel.activeTimer else { return "" }
        return Self.startFormatter.string(from: active.startDate)
    }

    private var cascade: some View {
        VStack(spacing: 6) {
            picker("Client", selection: clientBinding, options: clientOptions)
            picker("Project", selection: projectBinding, options: projectOptions)
                .disabled(projectOptions.count <= 1)
            picker("Sprint", selection: sprintBinding, options: sprintOptions)
                .disabled(sprintOptions.count <= 1)
            picker("Task", selection: taskBinding, options: taskOptions)
                .disabled(taskOptions.count <= 1)
        }
    }

    /// The cascade's rows are drawn here rather than with `PCCMenuPicker`'s
    /// own `.boxed` chrome: this card's ground is the accent fill, not
    /// glass, so its controls need white-on-accent chips instead of the
    /// chip background every other screen's picker draws.
    private func picker(
        _ label: String, selection: Binding<UUID?>, options: [(value: UUID?, title: String)]
    ) -> some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection.wrappedValue = option.value
                } label: {
                    if option.value == selection.wrappedValue {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 8)
                Text(options.first { $0.value == selection.wrappedValue }?.title ?? "Any")
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: PCCChassis.controlCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.16))
            )
            .contentShape(Rectangle())
        }
        .pccBorderlessMenu()
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    if timerViewModel.isRunning {
                        await timerViewModel.stop()
                        await onStopped()
                    } else if let container = picked.container {
                        await timerViewModel.start(container: container)
                    }
                }
            } label: {
                Label(
                    timerViewModel.isRunning ? "Stop" : "Start",
                    systemImage: timerViewModel.isRunning ? "stop.fill" : "play.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.accent(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .disabled(!timerViewModel.isRunning && picked.container == nil)
            .opacity(!timerViewModel.isRunning && picked.container == nil ? 0.5 : 1)

            // Discarding a running timer outright, rather than stopping it
            // into a Time Entry. Shown only while one is running, since
            // there's nothing to cancel otherwise.
            if timerViewModel.isRunning {
                Button {
                    Task { await timerViewModel.cancel() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Circle().fill(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Discard this timer without logging it")
            }
        }
    }

    // MARK: - Cascade options

    /// Every level offers an "Any" entry, which is both the empty selection
    /// and the way back up: picking Any at the Project level puts the timer
    /// back on the Client itself.
    private var clientOptions: [(value: UUID?, title: String)] {
        [(nil, "Any")] + viewModel.clients.map { (Optional($0.id), $0.name) }
    }

    private var projectOptions: [(value: UUID?, title: String)] {
        let projects = viewModel.workProjects
            .filter { picked.clientID == nil ? true : $0.clientID == picked.clientID }
            .sorted { $0.name < $1.name }
        return [(nil, "Any")] + projects.map { (Optional($0.id), $0.name) }
    }

    /// Sprints of the picked Project only — a Sprint is scoped to its
    /// Project for its lifetime (`CONTEXT.md`), so with no Project picked
    /// there is nothing to list.
    private var sprintOptions: [(value: UUID?, title: String)] {
        guard let projectID = picked.projectID else { return [(nil, "Any")] }
        let sprints = viewModel.sprints
            .filter { $0.projectID == projectID }
            .sorted { $0.startDate < $1.startDate }
        return [(nil, "Any")] + sprints.map { (Optional($0.id), $0.name) }
    }

    /// Incomplete Tasks inside the current cascade — a done Task isn't
    /// something to start a timer on. Narrowed by Sprint when one is
    /// picked, by Project otherwise, and by Client above that.
    private var taskOptions: [(value: UUID?, title: String)] {
        let clientProjectIDs = Set(
            viewModel.workProjects.filter { $0.clientID == picked.clientID }.map(\.id))
        let tasks = viewModel.tasks
            .filter { task in
                guard task.courseID == nil, !task.isComplete else { return false }
                if let sprintID = picked.sprintID { return task.sprintID == sprintID }
                if let projectID = picked.projectID { return task.projectID == projectID }
                guard picked.clientID != nil else { return true }
                guard let projectID = task.projectID else { return false }
                return clientProjectIDs.contains(projectID)
            }
            .sorted { $0.title < $1.title }
        return [(nil, "Any")] + tasks.map { (Optional($0.id), $0.title) }
    }

    // MARK: - Cascade bindings

    private var clientBinding: Binding<UUID?> {
        Binding(get: { picked.clientID }, set: { picked.setClient($0) })
    }

    private var projectBinding: Binding<UUID?> {
        Binding(get: { picked.projectID }, set: { picked.setProject($0) })
    }

    private var sprintBinding: Binding<UUID?> {
        Binding(get: { picked.sprintID }, set: { picked.setSprint($0) })
    }

    private var taskBinding: Binding<UUID?> {
        Binding(get: { picked.taskID }, set: { picked.taskID = $0 })
    }

    private static let startFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
