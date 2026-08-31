import SwiftUI

/// A Project's "% of Tasks done" indicator, shared by `ProjectsView`'s row
/// and `ProjectDetailView`'s header (a free function, not a method, since
/// both types need it) — a "dimension line" in the drafting sense: tick
/// marks at both ends and a measured span in between, the convention an
/// architectural drawing uses to call out a length, rather than a default
/// rounded `ProgressView` pill. `Projects`' own signature device, per its
/// "Drafting Table" vibe (`ScreenTheme.draftingTable` below) — everything
/// on this screen is meant to read like a measurement on a blueprint, and
/// a plain progress bar doesn't carry that association the way this does.
func projectProgressBar(_ fraction: Double, colorScheme: ColorScheme, theme: ScreenTheme) -> some View {
    HStack(spacing: 10) {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.panelLine(colorScheme))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)
                Rectangle()
                    .fill(theme.accent(colorScheme))
                    .frame(width: proxy.size.width * CGFloat(fraction), height: 3)
                    .frame(maxHeight: .infinity, alignment: .center)
                // The two end ticks — fixed at the track's own edges, not
                // at the fraction point, since a dimension line's ticks
                // mark the span being measured, not the current reading.
                tick(theme: theme, colorScheme: colorScheme).frame(width: 1)
                tick(theme: theme, colorScheme: colorScheme)
                    .frame(width: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 9)
        Text(fraction, format: .percent.precision(.fractionLength(0)))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(minWidth: 36, alignment: .trailing)
    }
}

/// One dimension-line end tick, shared by both ends in `projectProgressBar`.
private func tick(theme: ScreenTheme, colorScheme: ColorScheme) -> some View {
    Rectangle().fill(theme.panelLine(colorScheme))
}

/// Minimal Mac/iOS screen for ticket #3: lists Projects, and supports
/// creating, editing (renaming, setting/clearing a Deadline — ticket #5),
/// and deleting one. One shared SwiftUI view for both platforms — no
/// platform-specific chrome, per the ticket's "minimal" scope. Tapping a row
/// navigates into `ProjectDetailView` (ticket #18) rather than opening the
/// edit sheet directly — editing moved to that screen's own toolbar.
public struct ProjectsView: View {
    @ObservedObject private var viewModel: ProjectsViewModel

    public init(viewModel: ProjectsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ProjectsContent(viewModel: viewModel)
            .screenTheme(.draftingTable)
    }
}

/// The screen's actual content — split out from `ProjectsView` itself so
/// `.screenTheme(.draftingTable)` (applied in that struct's body, above)
/// is genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required, not optional —
/// `FinancesReportingView`/`FinancesReportingContent` hit this the hard
/// way first.
private struct ProjectsContent: View {
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var isPresentingNewProjectSheet = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.projects.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    projectList
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewProjectSheet = true
                    } label: {
                        Label("Add Project", systemImage: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Error", isPresented: isShowingError, presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $isPresentingNewProjectSheet) {
                ProjectFormSheet(title: "New Project", initialName: "", initialDueDate: nil) { values in
                    await viewModel.createProject(values)
                }
            }
        }
    }

    private var projectList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.projects) { project in
                    NavigationLink {
                        ProjectDetailView(
                            project: project,
                            viewModel: viewModel,
                            sprintsViewModel: viewModel.makeSprintsViewModel(for: project)
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(project.name)
                            if let clientName = viewModel.clientName(for: project) {
                                Text(clientName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let dueDate = project.dueDate {
                                Text(dueDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let fraction = viewModel.completionFraction(for: project) {
                                projectProgressBar(fraction, colorScheme: colorScheme, theme: theme)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { viewModel.projects[$0] }
                    Task {
                        for project in toDelete {
                            await viewModel.deleteProject(project)
                        }
                    }
                }
                .panelRows()
            }
        }
        .scrollContentBackground(.hidden)
        .background(DraftingGridBackground())
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(overallStatus)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// `.critical` when any Project is past its due date with incomplete
    /// Tasks — the same "read the lamp before the rows" device
    /// `OverviewView`'s own status strip uses.
    private var overallStatus: PanelStatus {
        hasOverdueProject ? .critical : .nominal
    }

    private var hasOverdueProject: Bool {
        viewModel.projects.contains { project in
            guard let dueDate = project.dueDate, dueDate < Date() else { return false }
            let fraction = viewModel.completionFraction(for: project) ?? 1
            return fraction < 1
        }
    }

    private var statusStripText: String {
        let count = viewModel.projects.count
        let noun = count == 1 ? "PROJECT" : "PROJECTS"
        let flagText = hasOverdueProject ? "OVERDUE" : "ON TRACK"
        return "\(count) \(noun)   ·   \(flagText)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Projects")
                .font(.headline)
            Text("Tap + to create your first Project.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DraftingGridBackground())
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { viewModel.errorMessage = nil } }
        )
    }
}

/// Shared create/edit form: the same sheet serves "New Project" and "Edit
/// Project" — a name field and a Deadline toggle (mirrors `TaskFormSheet`).
struct ProjectFormSheet: View {
    let title: String
    let onSave: (ProjectFormValues) async -> Void

    @State private var name: String
    @State private var hasDeadline: Bool
    @State private var dueDate: Date
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String, initialDueDate: Date?, onSave: @escaping (ProjectFormValues) async -> Void) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
        self._hasDeadline = State(initialValue: initialDueDate != nil)
        self._dueDate = State(initialValue: initialDueDate ?? Date())
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` unless the "Has deadline" toggle is on — SwiftUI's `DatePicker`
    /// has no built-in optional-date mode, so the toggle stands in for one.
    private var selectedDueDate: Date? {
        hasDeadline ? dueDate : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .pccField()
                }
                .panelRows()
                Section("Deadline") {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
                .panelRows()
            }
            .panelScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = ProjectFormValues(name: trimmedName, dueDate: selectedDueDate)
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}

/// A Project's detail screen (ticket #18): the Project's name/due date
/// read-only at the top (editing moved here from the list row, via the
/// toolbar's "Edit" button — same `ProjectFormSheet`/`onSave` wiring as
/// before), plus a "Sprints" section listing the Project's Sprints with
/// add/edit/delete.
struct ProjectDetailView: View {
    let project: Project
    @ObservedObject var viewModel: ProjectsViewModel
    @ObservedObject var sprintsViewModel: SprintsViewModel

    @State private var isPresentingEditSheet = false
    @State private var isPresentingNewSprintSheet = false
    @State private var editingSprint: Sprint?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    /// The freshest known copy of `project` — falls back to the value
    /// passed in if `viewModel.projects` hasn't (yet) reflected an edit.
    private var currentProject: Project {
        viewModel.projects.first(where: { $0.id == project.id }) ?? project
    }

    var body: some View {
        List {
            Section {
                Text(currentProject.name)
                    .font(.title3)
                if let dueDate = currentProject.dueDate {
                    Text(dueDate, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let fraction = viewModel.completionFraction(for: currentProject) {
                    projectProgressBar(fraction, colorScheme: colorScheme, theme: theme)
                }
            }
            .panelRows()
            Section("Sprints") {
                if sprintsViewModel.sprints.isEmpty {
                    Text("No Sprints yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sprintsViewModel.sprints) { sprint in
                        Button {
                            editingSprint = sprint
                        } label: {
                            VStack(alignment: .leading) {
                                Text(sprint.name)
                                Text("\(sprint.startDate, style: .date) – \(sprint.endDate, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif
                    }
                    .onDelete { offsets in
                        let toDelete = offsets.map { sprintsViewModel.sprints[$0] }
                        Task {
                            for sprint in toDelete {
                                await sprintsViewModel.deleteSprint(sprint)
                            }
                        }
                    }
                }
                Button {
                    isPresentingNewSprintSheet = true
                } label: {
                    Label("Add Sprint", systemImage: "plus")
                }
            }
            .panelRows()
        }
        .scrollContentBackground(.hidden)
        .background(DraftingGridBackground())
        .navigationTitle(currentProject.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isPresentingEditSheet = true
                }
            }
        }
        .task { await sprintsViewModel.load() }
        .refreshable { await sprintsViewModel.load() }
        .alert("Error", isPresented: isShowingSprintsError, presenting: sprintsViewModel.errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $isPresentingEditSheet) {
            ProjectFormSheet(
                title: "Edit Project",
                initialName: currentProject.name,
                initialDueDate: currentProject.dueDate
            ) { values in
                await viewModel.updateProject(currentProject, with: values)
            }
        }
        .sheet(isPresented: $isPresentingNewSprintSheet) {
            SprintFormSheet(title: "New Sprint", initialName: "", initialStartDate: Date(), initialEndDate: Date()) { values in
                await sprintsViewModel.createSprint(values)
            }
        }
        .sheet(item: $editingSprint) { sprint in
            SprintFormSheet(
                title: "Edit Sprint",
                initialName: sprint.name,
                initialStartDate: sprint.startDate,
                initialEndDate: sprint.endDate
            ) { values in
                await sprintsViewModel.updateSprint(sprint, with: values)
            }
        }
    }

    private var isShowingSprintsError: Binding<Bool> {
        Binding(
            get: { sprintsViewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { sprintsViewModel.errorMessage = nil } }
        )
    }
}

/// Shared create/edit form: the same sheet serves "New Sprint" and "Edit
/// Sprint" — a name field and start/end `DatePicker`s (mirrors
/// `ProjectFormSheet`). A Sprint's Project isn't editable here — it's set at
/// creation and never reassigned (`CONTEXT.md`).
struct SprintFormSheet: View {
    let title: String
    let onSave: (SprintFormValues) async -> Void

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialName: String,
        initialStartDate: Date,
        initialEndDate: Date,
        onSave: @escaping (SprintFormValues) async -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
        self._startDate = State(initialValue: initialStartDate)
        self._endDate = State(initialValue: initialEndDate)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && endDate >= startDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .pccField()
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                }
                .panelRows()
            }
            .panelScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = SprintFormValues(name: trimmedName, startDate: startDate, endDate: endDate)
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Drafting Table theme

extension ScreenTheme {
    /// `ProjectsView`'s own vibe: everything on this screen should read
    /// like a measurement on a blueprint. A technical blue accent in
    /// place of the app's teal-cyan and Finance's gold, and — unlike a
    /// generic "just go dark grey" dark mode — a dark mode that stays
    /// genuinely blue-toned throughout, since a real blueprint sheet
    /// doesn't lose its color at night, it just prints white-on-blue
    /// instead of blue-on-white. Signal colors are left as
    /// `ScreenTheme.default`'s — no urgency semantic needed changing here.
    fileprivate static let draftingTable = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x0B2647) : Color(hex: 0xF2F6FC) },
        panelSurface: { $0 == .dark ? Color(hex: 0x123661) : Color(hex: 0xFFFFFF) },
        panelLine: { $0 == .dark ? Color(hex: 0x2C5B96) : Color(hex: 0xC7D6EC) },
        accent: { $0 == .dark ? Color(hex: 0xD9E8FF) : Color(hex: 0x2F6FE4) },
        signalGreen: ScreenTheme.default.signalGreen,
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: ScreenTheme.default.signalRed
    )
}

// MARK: - Drafting grid background

/// This screen's signature device: an engineering-graph-paper grid behind
/// every panel — a fine 1-unit grid plus a heavier line every 5 units,
/// the real drafting-paper convention — instead of the shared chassis's
/// plain void + radial glow. Derives both grid tones from the active
/// theme's own `panelLine` color (full opacity for the heavy lines, a
/// diluted version for the fine ones) rather than adding bespoke grid
/// tokens to `ScreenTheme` for a device only this screen uses.
private struct DraftingGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private let cell: CGFloat = 14
    private let heavyEvery = 5

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.panelVoid(colorScheme)))

            var column = 0
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(lineColor(heavy: column % heavyEvery == 0)), lineWidth: 1)
                x += cell
                column += 1
            }

            var row = 0
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor(heavy: row % heavyEvery == 0)), lineWidth: 1)
                y += cell
                row += 1
            }
        }
        .ignoresSafeArea()
    }

    private func lineColor(heavy: Bool) -> Color {
        heavy ? theme.panelLine(colorScheme) : theme.panelLine(colorScheme).opacity(0.4)
    }
}
