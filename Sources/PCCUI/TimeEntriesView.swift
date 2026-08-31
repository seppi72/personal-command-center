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
public struct TimeEntriesView: View {
    @ObservedObject private var viewModel: TimeEntriesViewModel
    @ObservedObject private var timerViewModel: TimerViewModel

    public init(viewModel: TimeEntriesViewModel, timerViewModel: TimerViewModel) {
        self.viewModel = viewModel
        self.timerViewModel = timerViewModel
    }

    public var body: some View {
        TimeEntriesContent(viewModel: viewModel, timerViewModel: timerViewModel)
            .screenTheme(.punchClock)
    }
}

/// The screen's actual content — split out from `TimeEntriesView` itself so
/// `.screenTheme(.punchClock)` (applied in that struct's body, above) is
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    hero
                }
                Section {
                    statusStrip
                }
                Section {
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
                            .punchRow()
                        }
                    }
                }
            }
            .panelScreenBackground()
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
                idleHero
                itemPickerCard
            }
        }
        .punchRow()
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

    private func runningHero(for entry: TimeEntry) -> some View {
        PanelCard(minHeight: 300) {
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
                    // same, the discarded entry's "Punched In" row would
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
        PanelCard(minHeight: 300) {
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
                    // its "Punched In" state immediately, rather than only
                    // after a pull-to-refresh.
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
    /// picks up this screen's steel-blue accent instead of a generic tint.
    /// Switching tabs clears `timerSelectedItemID`: an id from the old
    /// kind's list wouldn't mean anything against the new kind's items.
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
        PanelCard {
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
    /// colors (steel-blue to start, red to stop) rather than the generic
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
    /// `formattedDuration(_:)` (this file, top level) — that one renders
    /// the compact "1H 32M" duration stamps below, this one the big ticking
    /// ":"-separated readout.
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

    private var statusStripText: String {
        let groups = viewModel.groupedTimeEntries
        let total = groups.reduce(0) { $0 + $1.totalDuration }
        return "\(groups.count) TRACKED   ·   \(formattedDuration(total)) TOTAL"
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
/// clears its peers" shape `TaskFormSheet` already has for its two.
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
            .panelScreenBackground()
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
/// bespoke re-theme, matching how `CourseDetailView`/`ProjectDetailView`
/// stay chassis-default while only their top-level list gets a screen's
/// signature device.
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
        .panelScreenBackground()
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
        return "\(currentGroup.entries.count) \(noun)   ·   \(formattedDuration(currentGroup.totalDuration)) TOTAL"
    }
}

private struct EntryRow: View {
    let entry: TimeEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.startDate, style: .date)
                    .font(.system(size: 13, weight: .semibold))
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
            if entry.isRunning {
                HStack(spacing: 5) {
                    StatusDot(.active)
                    Text("Punched In")
                        .pccPanelLabel()
                        .foregroundStyle(theme.signalGreen(colorScheme))
                }
            } else {
                DurationStamp(text: formattedDuration((entry.endDate ?? Date()).timeIntervalSince(entry.startDate)))
            }
        }
        .padding(.vertical, 6)
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

// MARK: - Punch Clock theme

extension ScreenTheme {
    /// `TimeEntriesView`'s own vibe: a punch clock / timesheet — cool
    /// steel-grey rather than another warm paper tone (Commitments/Clients/
    /// Courses already claimed that register), with a steel-blue ink
    /// accent for the duration stamp. Signal colors left as
    /// `ScreenTheme.default`'s.
    fileprivate static let punchClock = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x1B2023) : Color(hex: 0xE3E6E7) },
        panelSurface: { $0 == .dark ? Color(hex: 0x23282B) : Color(hex: 0xF5F6F2) },
        panelLine: { $0 == .dark ? Color(hex: 0x34393C) : Color(hex: 0xCBD1CD) },
        accent: { $0 == .dark ? Color(hex: 0x8FC1E0) : Color(hex: 0x2F5872) },
        signalGreen: ScreenTheme.default.signalGreen,
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: ScreenTheme.default.signalRed
    )
}

// MARK: - Punch row chrome

extension View {
    /// Strips a `List` row down to bare content — used for the hero timer
    /// (a `PanelCard`, which draws its own chrome) and for `GroupRow`
    /// (which draws its own bordered card), neither of which wants the
    /// chassis's own `panelRows()` card wrapped a second time around them.
    fileprivate func punchRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.vertical, 5)
    }
}

// MARK: - Group row

/// This screen's own row chrome for the totals list: a bordered card with
/// a left-edge accent stripe (steel-blue by default, green while that
/// container has the active timer running) rather than the shared
/// `panelRows()` look — the stripe is this row's own status indicator, in
/// place of every other screen's separate leading `StatusDot`.
private struct GroupRow: View {
    let group: TimeEntryGroup

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.label)
                    .font(.system(size: 15, weight: .semibold))
                if group.containsRunning {
                    HStack(spacing: 5) {
                        StatusDot(.active)
                        Text("Punched In")
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
            if !group.containsRunning {
                DurationStamp(text: formattedDuration(group.totalDuration))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: PCCChassis.cardCornerRadius, style: .continuous)
                .fill(theme.panelSurface(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: PCCChassis.cardCornerRadius, style: .continuous)
                        .strokeBorder(theme.panelLine(colorScheme), lineWidth: 1)
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(group.containsRunning ? theme.signalGreen(colorScheme) : theme.panelLine(colorScheme))
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .padding(.leading, 3)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 8, x: 0, y: 3)
        )
    }

    private var entryCountText: String {
        group.entries.count == 1 ? "1 Entry" : "\(group.entries.count) Entries"
    }
}

/// This screen's signature: a rotated, double-ruled "duration stamp"
/// reading like a rubber ink stamp pressed onto a time-card stub, standing
/// in for a plain HH:MM readout wherever a total is shown (the group
/// roster and each entry's own row).
private struct DurationStamp: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy, design: .monospaced))
            .foregroundStyle(theme.accent(colorScheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(theme.accent(colorScheme), lineWidth: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(theme.accent(colorScheme).opacity(0.5), lineWidth: 1)
                            .padding(3)
                    )
            )
            .rotationEffect(.degrees(-5))
    }
}

/// "1H 32M" past an hour, "37M" until then — the compact duration-stamp
/// format shared by `GroupRow`, `EntryRow`, and the status strips, distinct
/// from `TimeEntriesContent.formattedElapsed(_:)`'s ":"-separated ticking
/// readout in the hero. A free function rather than a method on any one
/// type, since none of its three callers has a natural claim to own it.
private func formattedDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 {
        return "\(hours)H \(String(format: "%02d", minutes))M"
    }
    return "\(minutes)M"
}
