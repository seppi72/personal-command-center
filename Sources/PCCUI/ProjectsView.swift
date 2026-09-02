import SwiftUI

/// A Project's "% of Tasks done" indicator — a "dimension line" in the
/// drafting sense: tick marks at both ends and a measured span in between,
/// the convention an architectural drawing uses to call out a length,
/// rather than a default rounded `ProgressView` pill. Shared by
/// `ProjectCard`'s grid cell and `ProjectDetailView`'s header (a free
/// function, not a method, since both types need it). Kept as this
/// screen's one signature device under the shared glass system (issue
/// #69) even though the bespoke "Drafting Table" vibe that originally
/// motivated it is gone — the percentage figure itself is set in
/// monospaced digits, per that issue's acceptance criteria.
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

/// Whether `project` is overdue — past its due date with incomplete Tasks.
/// Shared by `ProjectsContent`'s aggregate status strip
/// (`hasOverdueProject`) and each `ProjectCard`'s own due-date flag, so the
/// two can't drift apart into disagreeing about the same Project.
func projectIsOverdue(_ project: Project, completionFraction: Double?) -> Bool {
    guard let dueDate = project.dueDate, dueDate < Date() else { return false }
    return (completionFraction ?? 1) < 1
}

/// Minimal Mac/iOS screen for ticket #3: lists Projects, and supports
/// creating, editing (renaming, setting/clearing a Deadline — ticket #5),
/// and deleting one. One shared SwiftUI view for both platforms — no
/// platform-specific chrome, per the ticket's "minimal" scope.
///
/// On the shared Liquid Glass system since issue #69 — a grid of
/// `ProjectCard` bubbles (mirrors `CategoriesView`'s own grid+expand
/// shape), replacing the earlier drafting-table costume
/// (`DraftingGridBackground`, `ScreenTheme.draftingTable`) `git log` on
/// this file still shows. Tapping a card expands it into a centered
/// overlay showing its Sprints; reaching `ProjectDetailView` to rename the
/// Project, change its Deadline, or manage Sprints in full moved to a
/// "Manage Project" link inside that overlay, since a single tap is now
/// spent on the expand gesture instead of navigating directly.
public struct ProjectsView: View {
    @ObservedObject private var viewModel: ProjectsViewModel

    public init(viewModel: ProjectsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ProjectsContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `ProjectsView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required, not optional —
/// `FinancesReportingView`/`FinancesReportingContent` hit this the hard
/// way first.
private struct ProjectsContent: View {
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var isPresentingNewProjectSheet = false

    /// Which card (if any) is currently expanded, and the `SprintsViewModel`
    /// scoped to it — tapping a collapsed grid card sets both; tapping the
    /// scrim, the close button, or the same card again clears them. Mirrors
    /// `CategoriesContent.expandedCategoryID`; unlike that screen, expanding
    /// a Project also needs its own view model, since a Project's Sprints
    /// are loaded per-Project on demand rather than already held on
    /// `ProjectsViewModel` the way Category spending is.
    @State private var expandedProjectID: UUID?
    @State private var expandedSprintsViewModel: SprintsViewModel?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.projects.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    projectScroll
                }
            }
            .background(GlassScreenBackground())
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

    /// A `ScrollView` of `ProjectCard`s in a `LazyVGrid`, with a centered
    /// expand overlay above a dimmed scrim rather than something grown in
    /// place out of its source grid cell — the same shape, for the same two
    /// real-bug reasons, `CategoriesContent.categoryScroll`'s own doc
    /// comment records in full (`LazyVGrid` not honoring `zIndex` across
    /// its own cells, and a grown-in-place transition never actually
    /// reading as "growing").
    private var projectScroll: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusStrip
                    projectGrid
                }
                .padding(PCCChassis.outerMargin)
            }
            if let expandedProjectID, let project = project(withID: expandedProjectID),
                let sprintsViewModel = expandedSprintsViewModel {
                expandedOverlay(project, sprintsViewModel: sprintsViewModel)
            }
        }
        // On the enclosing `ZStack`, not the conditional content itself, so
        // it governs the whole insert/remove transition below rather than
        // only in-place property changes.
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: expandedProjectID)
    }

    private func project(withID id: UUID) -> Project? {
        viewModel.projects.first { $0.id == id }
    }

    /// A tap on a collapsed card expands it — see `expandedOverlay(_:sprintsViewModel:)`
    /// for where the expanded state actually renders. Deletion moved from
    /// the former `List`'s swipe-to-delete to a context menu, the same
    /// device `ClientCard` already uses for its own grid cells.
    private var projectGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            ForEach(viewModel.projects) { project in
                Button {
                    if expandedProjectID == project.id {
                        expandedProjectID = nil
                    } else {
                        expandedProjectID = project.id
                        expandedSprintsViewModel = viewModel.makeSprintsViewModel(for: project)
                    }
                } label: {
                    ProjectCard(
                        project: project,
                        clientName: viewModel.clientName(for: project),
                        completionFraction: viewModel.completionFraction(for: project),
                        isExpanded: false
                    )
                }
                .buttonStyle(ProjectCardPressStyle())
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteProject(project) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    /// The single floating, enlarged `ProjectCard` for whichever Project is
    /// tapped, its Sprints loaded into `sprintsViewModel` as soon as it
    /// appears (`.task(id:)`, keyed on the Project's id) — a dimmed scrim
    /// behind it (tap to dismiss), a close button on the card itself, and a
    /// "Manage Project" link down to `ProjectDetailView` now that a tap on
    /// the collapsed card spends itself on expanding rather than
    /// navigating (mirrors `CategoriesContent.expandedOverlay(_:)`, with
    /// `SprintsViewModel` swapped in for the Category screen's own
    /// already-loaded spending totals).
    private func expandedOverlay(_ project: Project, sprintsViewModel: SprintsViewModel) -> some View {
        ZStack {
            // Its own opacity-only transition — kept separate from the
            // card's `.scale` transition below, same reasoning as
            // `CategoriesContent.expandedOverlay(_:)`.
            Rectangle()
                .fill(scrimColor)
                .ignoresSafeArea()
                .onTapGesture { expandedProjectID = nil }
                .transition(.opacity)
            VStack(spacing: 14) {
                ProjectCard(
                    project: project,
                    clientName: viewModel.clientName(for: project),
                    completionFraction: viewModel.completionFraction(for: project),
                    isExpanded: true,
                    sprints: sprintsViewModel.sprints
                )
                .background(bubbleShadow)
                .overlay(alignment: .topTrailing) {
                    Button {
                        expandedProjectID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
                NavigationLink {
                    ProjectDetailView(project: project, viewModel: viewModel, sprintsViewModel: sprintsViewModel)
                } label: {
                    Label("Manage Project", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
                .foregroundStyle(theme.accent(colorScheme))
            }
            .frame(maxWidth: 360)
            // Distinct identity per Project so switching which card is
            // expanded is a genuine remove-then-insert, and so `.task(id:)`
            // below re-fires for the newly expanded Project rather than
            // treating a swap as an in-place update of the same view.
            .id(project.id)
            .task(id: project.id) { await sprintsViewModel.load() }
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .zIndex(1)
    }

    private var scrimColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.6 : 0.28)
    }

    /// A drop shadow behind the expanded card — kept off the shared
    /// `GlassBubble` itself (which the collapsed grid cells also use)
    /// since only the enlarged overlay instance needs the heavier "lifted
    /// toward the viewer" shadow.
    private var bubbleShadow: some View {
        RoundedRectangle(cornerRadius: GlassBubbleStyle.gridCell.cornerRadius, style: .continuous)
            .fill(Color.clear)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.16), radius: 26, x: 0, y: 14)
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
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    /// `.critical` when any Project is past its due date with incomplete
    /// Tasks — the same "read the lamp before the rows" device
    /// `OverviewView`'s own status strip uses.
    private var overallStatus: PanelStatus {
        hasOverdueProject ? .critical : .nominal
    }

    private var hasOverdueProject: Bool {
        viewModel.projects.contains { projectIsOverdue($0, completionFraction: viewModel.completionFraction(for: $0)) }
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
/// Left in the shared chassis look rather than a bespoke glass re-theme — a
/// `Form`'s native controls don't read as "liquid glass" however they're
/// dressed, so there's nothing this screen's own device would add here
/// (mirrors `AccountFormSheet`'s identical reasoning).
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
            .glassScreenBackground()
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
/// read-only at the top (editing reached via the toolbar's "Edit" button —
/// same `ProjectFormSheet`/`onSave` wiring as before), plus a "Sprints"
/// section listing the Project's Sprints with add/edit/delete. Reached from
/// `ProjectsView`'s expanded-card overlay via its "Manage Project" link
/// (issue #69) rather than a direct row tap, since a tap on the collapsed
/// grid card now expands it instead.
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
        .glassScreenBackground()
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
            .glassScreenBackground()
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

/// The tap feedback every collapsed `ProjectCard` button uses — a brief
/// press-down scale dip, the same device `CategoryCard`'s own press style
/// uses, scoped separately per screen rather than shared, matching that
/// type's own precedent.
private struct ProjectCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Project card

/// One Project's card: the shared `GlassBubble` surface (`.gridCell` size)
/// with this screen's own content on it — name, Client, due date, and the
/// `projectProgressBar` dimension line. Used two ways: `isExpanded: false`
/// as the plain collapsed grid cell, and `isExpanded: true` as the single
/// centered card `ProjectsContent.expandedOverlay(_:sprintsViewModel:)`
/// paints above a dimmed scrim, additionally passed that Project's
/// `sprints` to reveal (mirrors `CategoryCard`'s own two-ways-used shape).
private struct ProjectCard: View {
    let project: Project
    let clientName: String?
    let completionFraction: Double?
    let isExpanded: Bool
    var sprints: [Sprint] = []

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let baseHeight: CGFloat = 140
    private static let style: GlassBubbleStyle = .gridCell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(project.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
            if let clientName {
                Text(clientName.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
            if let dueDate = project.dueDate {
                Text(dueDate, style: .date)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isOverdue ? theme.signalRed(colorScheme) : .secondary)
                    .padding(.top, clientName == nil ? 10 : 3)
            }
            if let completionFraction {
                projectProgressBar(completionFraction, colorScheme: colorScheme, theme: theme)
                    .padding(.top, 12)
            }
            if isExpanded {
                sprintsSection
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: Self.baseHeight, alignment: .topLeading)
        .glassBubble(Self.style)
    }

    private var isOverdue: Bool {
        projectIsOverdue(project, completionFraction: completionFraction)
    }

    // MARK: Sprints (expanded reveal)

    @ViewBuilder
    private var sprintsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1)
                .opacity(0.7)
                .padding(.bottom, 2)
            if sprints.isEmpty {
                Text("No Sprints yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sprints) { sprint in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(sprint.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.dateRangeText(sprint))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private static func dateRangeText(_ sprint: Sprint) -> String {
        "\(Self.dateFormatter.string(from: sprint.startDate))–\(Self.dateFormatter.string(from: sprint.endDate))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
