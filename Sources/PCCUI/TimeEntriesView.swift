import SwiftUI

/// Minimal Mac/iOS screen for ticket #27, absorbing ticket #28's live-timer
/// control: a big elapsed-time hero at the top — pick a Task/Project/
/// Client/Course and Start, or Stop/Cancel whatever's already running —
/// with every container that has logged time listed below it, bucketed and
/// totaled (`TimeEntriesViewModel.groupedTimeEntries`) rather than shown as
/// a flat per-entry log. This used to be two screens (a standalone `Timer`
/// alongside this one); per direct product feedback the two are one screen
/// now — starting a timer and seeing where the hours went are the same
/// task, not two. Tapping a group drills into its individual entries for
/// edit/delete (`TimeEntryGroupDetailView`); manual retroactive logging (a
/// full start/end/notes entry not tied to the live timer) stays available
/// from the toolbar's +. One shared SwiftUI view for both platforms — no
/// platform-specific chrome, per this repo's "minimal" scope.
///
/// On the shared Liquid Glass system since issue #70 — full-width
/// `GlassBubble` rows on `GlassScreenBackground()`, replacing the earlier
/// punch-clock costume (steel-grey chassis, a rotated double-ruled
/// ink-stamp, a bordered card with a left-edge accent stripe) `git log` on
/// this file still shows. The duration stamp survives as this screen's
/// signature device — see `DurationStamp` below — but now renders (and
/// ticks) for a *running* Time Entry too, where it used to be hidden behind
/// a plain "Punched In" label; that's what makes a live entry's duration
/// readable at a glance rather than just its aliveness.
public struct TimeEntriesView: View {
    @ObservedObject private var viewModel: TimeEntriesViewModel
    @ObservedObject private var timerViewModel: TimerViewModel

    public init(viewModel: TimeEntriesViewModel, timerViewModel: TimerViewModel) {
        self.viewModel = viewModel
        self.timerViewModel = timerViewModel
    }

    public var body: some View {
        TimeEntriesContent(viewModel: viewModel, timerViewModel: timerViewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `TimeEntriesView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct TimeEntriesContent: View {
    @ObservedObject var viewModel: TimeEntriesViewModel
    @ObservedObject var timerViewModel: TimerViewModel

    /// The hero timer's own pending selection — separate from
    /// `OverviewView`'s identical `@State` for its mini Timer; each screen
    /// owns its own in-progress pick before `timerViewModel.start(container:)`
    /// commits it, the same way two independent forms would.
    @State private var timerSelectedKind: ContainerKind = .task
    @State private var timerSelectedItemID: UUID?
    @State private var isPresentingNewEntrySheet = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    /// A `ScrollView` of glass panels rather than a `List` — the hero, the
    /// picker, and every group row draw their own translucent
    /// Material-backed shape (the shared `GlassBubble`), which a `List`'s
    /// opaque native row chrome can't host (mirrors `TasksView`'s own move
    /// from `List` to `ScrollView` + custom bubbles for the same reason).
    /// One outer padding on the whole `VStack` — `PCCChassis.outerMargin`
    /// — replaces what used to be the `List`'s own frame padding.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    statusStrip
                    groupsSection
                }
                .padding(PCCChassis.outerMargin)
            }
            .background(GlassScreenBackground())
            .navigationTitle("Time Entries")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewEntrySheet = true
                    } label: {
                        Label("Add Time Entry", systemImage: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .task { await timerViewModel.load() }
            .refreshable {
                async let entriesLoad: Void = viewModel.load()
                async let timerLoad: Void = timerViewModel.load()
                _ = await (entriesLoad, timerLoad)
            }
            .errorAlert($viewModel.errorMessage)
            .errorAlert($timerViewModel.errorMessage)
            .sheet(isPresented: $isPresentingNewEntrySheet) {
                TimeEntryFormSheet(
                    title: "New Time Entry",
                    initialValues: nil,
                    tasks: viewModel.tasks,
                    projects: viewModel.projects,
                    clients: viewModel.clients,
                    courses: viewModel.courses
                ) { values in
                    await viewModel.createTimeEntry(values)
                }
            }
        }
    }

    // MARK: - Hero timer

    private var hero: some View {
        Group {
            if let activeTimer = timerViewModel.activeTimer {
                runningHero(for: activeTimer)
            } else {
                VStack(spacing: 20) {
                    idleHero
                    itemPickerCard
                }
            }
        }
    }

    private var readoutColor: Color {
        theme.accent(colorScheme)
    }

    /// Mirrors `OverviewView`'s own `panelHeader` — a `StatusDot` plus an
    /// uppercase tracked-out nameplate, no chevron here since this hero has
    /// nowhere further to navigate to.
    private func panelHeader(_ title: String, systemImage: String, status: PanelStatus) -> some View {
        HStack(spacing: 8) {
            StatusDot(status)
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// This screen's own glass panel — the counterpart to
    /// `FinancesReportingContent.glassPanel(content:)`, with a configurable
    /// floor so the hero (300pt, same as the old `PanelCard(minHeight:
    /// 300)`) and the shorter item picker (220pt, `PanelCard`'s own default)
    /// read as two different sizes of the same device rather than one
    /// fixed-height box repeated twice.
    private func heroPanel<Content: View>(
        minHeight: CGFloat = 220, @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .glassBubble(.fullWidth)
    }

    private func runningHero(for entry: TimeEntry) -> some View {
        heroPanel(minHeight: 300) {
            VStack(spacing: 20) {
                panelHeader("Timer", systemImage: "stopwatch", status: .active)
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Text(heroContainerLabel(for: entry))
                        .pccPanelLabel()
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: entry.startDate, by: 1)) { context in
                        Text(Self.formattedElapsed(context.date.timeIntervalSince(entry.startDate)))
                            .font(.pccReadout(64))
                            .foregroundStyle(readoutColor)
                    }
                    Text("Started \(entry.startDate, style: .relative) ago")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                bigButton("Stop", tint: theme.signalRed(colorScheme)) {
                    // Also reloads the roster below, not just the hero —
                    // `viewModel` and `timerViewModel` are independent
                    // ObservableObjects with no cross-notification of their
                    // own, so without this the just-completed entry
                    // wouldn't appear in its Task/Project/Client/Course's
                    // group until the next pull-to-refresh.
                    Task {
                        await timerViewModel.stop()
                        await viewModel.load()
                    }
                }
                Button("Cancel Timer", role: .destructive) {
                    // Reloads the roster too — since Start now does the
                    // same, the discarded entry's "running" row would
                    // otherwise linger in `viewModel.timeEntries` as stale
                    // state until the next pull-to-refresh.
                    Task {
                        await timerViewModel.cancel()
                        await viewModel.load()
                    }
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var idleHero: some View {
        heroPanel(minHeight: 300) {
            VStack(spacing: 20) {
                panelHeader("Timer", systemImage: "stopwatch", status: .idle)
                Spacer(minLength: 0)
                kindTabs
                Text(Self.formattedElapsed(0))
                    .font(.pccReadout(64))
                    .foregroundStyle(.secondary.opacity(0.35))
                Text(timerSelectedItemID == nil ? "Choose a \(timerSelectedKind.title) below to start" : "Ready to start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                bigButton("Start", tint: readoutColor) {
                    guard let container else { return }
                    // Also reloads the roster below (see the Stop button's
                    // own comment) so the newly-started entry's group shows
                    // its running state immediately, rather than only after
                    // a pull-to-refresh.
                    Task {
                        await timerViewModel.start(container: container)
                        await viewModel.load()
                    }
                }
                .disabled(container == nil)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The segmented Task/Project/Client/Course tab row — the selected tab
    /// picks up this screen's accent instead of a generic tint. Switching
    /// tabs clears `timerSelectedItemID`: an id from the old kind's list
    /// wouldn't mean anything against the new kind's items.
    private var kindTabs: some View {
        HStack(spacing: 4) {
            ForEach(ContainerKind.allCases) { kind in
                Button {
                    guard kind != timerSelectedKind else { return }
                    timerSelectedKind = kind
                    timerSelectedItemID = nil
                } label: {
                    Text(kind.title)
                        .font(.subheadline.weight(kind == timerSelectedKind ? .bold : .regular))
                        .foregroundStyle(kind == timerSelectedKind ? readoutColor : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(kind == timerSelectedKind ? readoutColor.opacity(0.15) : Color.clear)
                        )
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
        }
    }

    private var itemPickerCard: some View {
        heroPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a \(timerSelectedKind.title)")
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
                if currentItems.isEmpty {
                    Text("No \(timerSelectedKind.title)s yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(currentItems, id: \.id) { item in
                            itemRow(item)
                        }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: (id: UUID, title: String)) -> some View {
        Button {
            timerSelectedItemID = item.id
        } label: {
            HStack {
                Text(item.title)
                Spacer()
                if timerSelectedItemID == item.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(readoutColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: PCCChassis.controlCornerRadius, style: .continuous)
                    .fill(timerSelectedItemID == item.id ? readoutColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PCCChassis.controlCornerRadius, style: .continuous)
                    .strokeBorder(
                        timerSelectedItemID == item.id ? readoutColor.opacity(0.4) : theme.panelLine(colorScheme),
                        lineWidth: 1)
            )
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    /// A large pill-shaped call-to-action button — Start/Stop, spanning
    /// most of the hero panel's width, tinted with this screen's signal
    /// colors (accent green to start, red to stop) rather than the generic
    /// accent color a plain `.borderedProminent` button would default to.
    private func bigButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.pccReadout(17, weight: .semibold))
                .tracking(1.2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
    }

    private var container: TimeEntryContainer? {
        guard let timerSelectedItemID else { return nil }
        switch timerSelectedKind {
        case .task: return .task(timerSelectedItemID)
        case .project: return .project(timerSelectedItemID)
        case .client: return .client(timerSelectedItemID)
        case .course: return .course(timerSelectedItemID)
        }
    }

    private var currentItems: [(id: UUID, title: String)] {
        switch timerSelectedKind {
        case .task: return timerViewModel.tasks.map { ($0.id, $0.title) }
        case .project: return timerViewModel.projects.map { ($0.id, $0.name) }
        case .client: return timerViewModel.clients.map { ($0.id, $0.name) }
        case .course: return timerViewModel.courses.map { ($0.id, $0.name) }
        }
    }

    /// The name of whichever Task/Project/Client/Course `entry` is attached
    /// to — looked up from `timerViewModel`'s own copies of the picker
    /// lists (it loads its own, independently of `viewModel`'s, the same
    /// redundancy `OverviewView`'s mini Timer already accepts) rather than
    /// `viewModel.containerLabel(for:)`, since the hero only ever observes
    /// `timerViewModel`.
    private func heroContainerLabel(for entry: TimeEntry) -> String {
        if let taskID = entry.taskID {
            return timerViewModel.tasks.first { $0.id == taskID }?.title ?? "Unknown Task"
        }
        if let projectID = entry.projectID {
            return timerViewModel.projects.first { $0.id == projectID }?.name ?? "Unknown Project"
        }
        if let clientID = entry.clientID {
            return timerViewModel.clients.first { $0.id == clientID }?.name ?? "Unknown Client"
        }
        if let courseID = entry.courseID {
            return timerViewModel.courses.first { $0.id == courseID }?.name ?? "Unknown Course"
        }
        return "Unattached"
    }

    /// "H:MM:SS" once past an hour, "MM:SS" until then — a Timer runs
    /// open-ended (no set session length, unlike a Pomodoro countdown), so
    /// this counts up rather than down. Also used, at `0`, to render the
    /// idle hero's dimmed placeholder digits. Distinct from
    /// `TimeEntriesViewModel.formattedDuration(_:)` (this screen's compact
    /// "1H 32M" duration-stamp format) — this one is the big ticking
    /// ":"-separated readout, and stays here rather than moving onto a view
    /// model since it's the hero's own display concern, not a value either
    /// view model stores or a unit test needs to pin down independent of
    /// this view (unlike the duration-stamp format, which several rows
    /// share and issue #70 moved onto `TimeEntriesViewModel` for exactly
    /// that reason).
    fileprivate static func formattedElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(timerViewModel.isRunning ? .active : .idle)
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

    private var statusStripText: String {
        let groups = viewModel.groupedTimeEntries
        let total = groups.reduce(0) { $0 + $1.totalDuration }
        return "\(groups.count) TRACKED   ·   \(TimeEntriesViewModel.formattedDuration(total)) TOTAL"
    }

    // MARK: - Groups

    private var groupsSection: some View {
        VStack(spacing: 14) {
            if viewModel.groupedTimeEntries.isEmpty {
                emptyGroupsRow
            } else {
                ForEach(viewModel.groupedTimeEntries) { group in
                    NavigationLink {
                        TimeEntryGroupDetailView(group: group, viewModel: viewModel)
                    } label: {
                        GroupRow(group: group)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
        }
    }

    private var emptyGroupsRow: some View {
        Text("No time logged yet. Start the timer above, or add one manually.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }
}

/// Shared create/edit form: the same sheet serves "New Time Entry" and
/// "Edit Time Entry" — a start/end time, optional notes, and a container
/// picker that attaches to exactly one Task, Project, Client, or Course
/// (ADR-0004). Picking one clears the other three, the same "selecting one
/// clears its peers" shape `TaskFormSheet` already has for its two. Its
/// Section stays in the shared chassis look — a `Form`'s native controls
/// don't read as glass however they're dressed (`AccountFormSheet`'s doc
/// comment carries this reasoning in full) — but its ground now repaints to
/// `GlassScreenBackground()` via `glassScreenBackground()`, per issue #70.
struct TimeEntryFormSheet: View {
    let title: String
    let tasks: [PCCTask]
    let projects: [Project]
    let clients: [PCCClient]
    let courses: [Course]
    let onSave: (TimeEntryFormValues) async -> Void

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String
    @State private var taskID: UUID?
    @State private var projectID: UUID?
    @State private var clientID: UUID?
    @State private var courseID: UUID?
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialValues: TimeEntryFormValues?,
        tasks: [PCCTask],
        projects: [Project],
        clients: [PCCClient],
        courses: [Course],
        onSave: @escaping (TimeEntryFormValues) async -> Void
    ) {
        self.title = title
        self.tasks = tasks
        self.projects = projects
        self.clients = clients
        self.courses = courses
        self.onSave = onSave
        let defaultStart = Date()
        self._startDate = State(initialValue: initialValues?.startDate ?? defaultStart)
        self._endDate = State(initialValue: initialValues?.endDate ?? defaultStart.addingTimeInterval(3600))
        self._notes = State(initialValue: initialValues?.notes ?? "")
        self._taskID = State(initialValue: initialValues?.taskID)
        self._projectID = State(initialValue: initialValues?.projectID)
        self._clientID = State(initialValue: initialValues?.clientID)
        self._courseID = State(initialValue: initialValues?.courseID)
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var isEndAfterStart: Bool {
        endDate > startDate
    }

    /// Exactly one of the four pickers must be set before Save is enabled —
    /// mirrors the backend's own "exactly one" validation (ADR-0004) rather
    /// than letting the owner submit a request the server will just reject.
    private var hasExactlyOneContainer: Bool {
        TimeEntryContainer(taskID: taskID, projectID: projectID, clientID: clientID, courseID: courseID) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Starts", selection: $startDate)
                    DatePicker("Ends", selection: $endDate)
                    if !isEndAfterStart {
                        Text("End time must be after start time.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField("Notes", text: $notes)
                        .pccField()
                }
                .panelRows()

                Section("Attached to") {
                    PCCMenuPicker(
                        "Task", selection: $taskID,
                        options: [(UUID?.none, "None")] + tasks.map { (Optional($0.id), $0.title) }
                    )
                    .onChange(of: taskID) { newValue in
                        if newValue != nil { clearContainer(except: \Self.taskID) }
                    }
                    PCCMenuPicker(
                        "Project", selection: $projectID,
                        options: [(UUID?.none, "None")] + projects.map { (Optional($0.id), $0.name) }
                    )
                    .onChange(of: projectID) { newValue in
                        if newValue != nil { clearContainer(except: \Self.projectID) }
                    }
                    PCCMenuPicker(
                        "Client", selection: $clientID,
                        options: [(UUID?.none, "None")] + clients.map { (Optional($0.id), $0.name) }
                    )
                    .onChange(of: clientID) { newValue in
                        if newValue != nil { clearContainer(except: \Self.clientID) }
                    }
                    PCCMenuPicker(
                        "Course", selection: $courseID,
                        options: [(UUID?.none, "None")] + courses.map { (Optional($0.id), $0.name) }
                    )
                    .onChange(of: courseID) { newValue in
                        if newValue != nil { clearContainer(except: \Self.courseID) }
                    }
                    if !hasExactlyOneContainer {
                        Text("Choose exactly one Task, Project, Client, or Course.")
                            .font(.caption)
                            .foregroundStyle(.red)
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
                        let values = TimeEntryFormValues(
                            startDate: startDate,
                            endDate: endDate,
                            notes: trimmedNotes,
                            taskID: taskID,
                            projectID: projectID,
                            clientID: clientID,
                            courseID: courseID
                        )
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(!isEndAfterStart || !hasExactlyOneContainer)
                }
            }
        }
    }

    /// Clears every container field except `keyPath` — called whenever one
    /// picker gains a non-`nil` selection, so at most one is ever set at a
    /// time (ADR-0004).
    private func clearContainer(except keyPath: PartialKeyPath<TimeEntryFormSheet>) {
        if keyPath != \Self.taskID { taskID = nil }
        if keyPath != \Self.projectID { projectID = nil }
        if keyPath != \Self.clientID { clientID = nil }
        if keyPath != \Self.courseID { courseID = nil }
    }
}

/// A single container's drill-down (ticket #27's "how many hours for each
/// Task" grouping, ticket #28's live timer merged in above it) — every
/// individual Time Entry making up one `TimeEntryGroup`, in case the owner
/// needs to edit or delete a specific one rather than just seeing its
/// total. Left in the shared chassis look (`panelRows()`) rather than a
/// bespoke re-theme, matching how `ProjectDetailView` stays chassis-default
/// while only its parent screen's top-level list gets a screen's signature
/// device — but its ground repaints to `GlassScreenBackground()` via
/// `glassScreenBackground()`, per issue #70, since it's still pushed from
/// a screen now on the glass system.
private struct TimeEntryGroupDetailView: View {
    let group: TimeEntryGroup
    @ObservedObject var viewModel: TimeEntriesViewModel
    @State private var editingEntry: TimeEntry?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    /// The freshest known copy of this group — falls back to the value
    /// passed in if a mutation (edit/delete) hasn't (yet) been reflected
    /// back into `viewModel.groupedTimeEntries`. Mirrors
    /// `CourseDetailView.currentCourse`'s same fallback shape.
    private var currentGroup: TimeEntryGroup {
        viewModel.groupedTimeEntries.first { $0.id == group.id } ?? group
    }

    private var sortedEntries: [TimeEntry] {
        currentGroup.entries.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        List {
            Section {
                totalStrip
            }
            Section {
                ForEach(sortedEntries) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        EntryRow(entry: entry)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { sortedEntries[$0] }
                    Task {
                        for entry in toDelete {
                            await viewModel.deleteTimeEntry(entry)
                        }
                    }
                }
                .panelRows()
            }
        }
        .glassScreenBackground()
        .navigationTitle(currentGroup.label)
        .errorAlert($viewModel.errorMessage)
        .sheet(item: $editingEntry) { entry in
            TimeEntryFormSheet(
                title: "Edit Time Entry",
                initialValues: TimeEntryFormValues(
                    startDate: entry.startDate,
                    // A running timer (ticket #28) has no `endDate` yet —
                    // default the field to "now" so the form always shows a
                    // concrete end time to adjust. Saving from here
                    // completes the timer through the regular edit
                    // endpoint, an alternate path to the same result as
                    // `TimerViewModel.stop()`.
                    endDate: entry.endDate ?? Date(),
                    notes: entry.notes,
                    taskID: entry.taskID,
                    projectID: entry.projectID,
                    clientID: entry.clientID,
                    courseID: entry.courseID
                ),
                tasks: viewModel.tasks,
                projects: viewModel.projects,
                clients: viewModel.clients,
                courses: viewModel.courses
            ) { values in
                await viewModel.updateTimeEntry(entry, with: values)
            }
        }
    }

    private var totalStrip: some View {
        HStack(spacing: 10) {
            StatusDot(currentGroup.containsRunning ? .active : .idle)
            Text(totalStripText)
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

    private var totalStripText: String {
        let noun = currentGroup.entries.count == 1 ? "ENTRY" : "ENTRIES"
        return "\(currentGroup.entries.count) \(noun)   ·   \(TimeEntriesViewModel.formattedDuration(currentGroup.totalDuration)) TOTAL"
    }
}

private struct EntryRow: View {
    let entry: TimeEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.startDate, style: .date)
                        .font(.system(size: 13, weight: .semibold))
                    if entry.isRunning {
                        runningBadge
                    }
                }
                Text(rangeText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let notes = entry.notes {
                    Text(notes)
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            durationStamp
        }
        .padding(.vertical, 6)
    }

    private var runningBadge: some View {
        HStack(spacing: 4) {
            StatusDot(.active)
            Text("Running")
                .pccPanelLabel()
                .foregroundStyle(theme.signalGreen(colorScheme))
        }
    }

    /// Ticks once a second while `entry` is still running (`endDate ==
    /// nil`) rather than freezing at whatever value was true when this row
    /// last rendered — the domain rule that at most one Time Entry runs at
    /// a time (`CONTEXT.md`'s Time Entry definition) means at most one row
    /// in the whole app ever pays this cost. A stopped entry's stamp is
    /// plain static text, same as every other duration on this screen.
    @ViewBuilder
    private var durationStamp: some View {
        if entry.isRunning {
            TimelineView(.periodic(from: entry.startDate, by: 1)) { context in
                DurationStamp(text: TimeEntriesViewModel.formattedDuration(context.date.timeIntervalSince(entry.startDate)))
            }
        } else {
            DurationStamp(
                text: TimeEntriesViewModel.formattedDuration((entry.endDate ?? Date()).timeIntervalSince(entry.startDate)))
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private var rangeText: String {
        let start = Self.timeFormatter.string(from: entry.startDate)
        guard let endDate = entry.endDate else { return "\(start) –" }
        return "\(start) – \(Self.timeFormatter.string(from: endDate))"
    }
}

// MARK: - Group row

/// One `TimeEntryGroup`'s row: the shared `GlassBubble` surface
/// (`.fullWidth` size) with this screen's own content on it — the group's
/// label, a "Running"/entry-count subline, and the `DurationStamp` hero
/// figure — mirroring `TaskBubble`'s identical shape (bubble + leading
/// label stack + trailing figure). Replaces the prior bespoke card with a
/// left-edge accent stripe; a running group's own signal now lives in the
/// "Running" `StatusDot` line and in the stamp itself ticking, not in a
/// stripe of color down the card's edge.
private struct GroupRow: View {
    let group: TimeEntryGroup

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.label)
                    .font(.system(size: 15, weight: .semibold))
                if group.containsRunning {
                    HStack(spacing: 5) {
                        StatusDot(.active)
                        Text("Running")
                            .pccPanelLabel()
                            .foregroundStyle(theme.signalGreen(colorScheme))
                    }
                } else {
                    Text(entryCountText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            durationStamp
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassBubble(Self.style)
    }

    /// Ticks once a second while the group has a running entry in it, for
    /// the same reason `EntryRow.durationStamp` does — see that property's
    /// doc comment.
    @ViewBuilder
    private var durationStamp: some View {
        if group.containsRunning {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                DurationStamp(text: TimeEntriesViewModel.formattedDuration(group.totalDuration))
            }
        } else {
            DurationStamp(text: TimeEntriesViewModel.formattedDuration(group.totalDuration))
        }
    }

    private var entryCountText: String {
        group.entries.count == 1 ? "1 Entry" : "\(group.entries.count) Entries"
    }
}

/// This screen's signature device, kept through the glass migration (issue
/// #70): a small glass capsule holding the duration in monospaced digits —
/// the glass counterpart to the old rotated, double-ruled ink stamp, cut
/// from the same glass every bubble on this screen uses (mirrors
/// `TasksView`'s identical redraw of its own `OverdueBadge`, issue #68).
/// Always the theme's plain accent color, never signal-colored — a
/// duration has no sign to color by, the same reasoning
/// `WorkHoursRowBubble` already gives for its own total figure; a running
/// vs. stopped Time Entry is told apart by the "Running" `StatusDot` next
/// to this stamp, and by the stamp actually ticking while live, not by its
/// own color.
private struct DurationStamp: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(theme.accent(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(GlassBubble.tint(for: colorScheme)))
                    .overlay(Capsule().strokeBorder(GlassBubble.rimColor(theme, colorScheme), lineWidth: GlassBubble.rimWidth))
            )
    }
}
