import SwiftUI

/// Minimal Mac/iOS screen for ticket #27: lists Time Entries, and supports
/// creating, editing, and deleting one — each attached to exactly one Task,
/// Project, Client, or Course (ADR-0004). One shared SwiftUI view for both
/// platforms — no platform-specific chrome, per the ticket's "minimal" scope
/// (mirrors `TasksView`/`PersonalCommitmentsView`).
public struct TimeEntriesView: View {
    @ObservedObject private var viewModel: TimeEntriesViewModel
    @State private var isPresentingNewEntrySheet = false
    @State private var editingEntry: TimeEntry?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    public init(viewModel: TimeEntriesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.timeEntries.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    entryList
                }
            }
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
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
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
            .sheet(item: $editingEntry) { entry in
                TimeEntryFormSheet(
                    title: "Edit Time Entry",
                    initialValues: TimeEntryFormValues(
                        startDate: entry.startDate,
                        // A running timer (ticket #28) has no `endDate` yet
                        // — default the field to "now" so the form always
                        // shows a concrete end time to adjust. Saving from
                        // here completes the timer through the regular edit
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
    }

    private var entryList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.timeEntries) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(containerLabel(for: entry))
                            Text(entry.startDate, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if entry.isRunning {
                                HStack(spacing: 5) {
                                    StatusDot(.active)
                                    Text("Running")
                                        .pccPanelLabel()
                                        .foregroundStyle(theme.accent(colorScheme))
                                }
                            }
                            if let notes = entry.notes {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { viewModel.timeEntries[$0] }
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

    private var runningCount: Int {
        viewModel.timeEntries.filter(\.isRunning).count
    }

    private var overallStatus: PanelStatus {
        runningCount > 0 ? .active : .idle
    }

    private var statusStripText: String {
        let count = viewModel.timeEntries.count
        let noun = count == 1 ? "ENTRY" : "ENTRIES"
        let flagText = runningCount > 0 ? "\(runningCount) RUNNING" : "NONE RUNNING"
        return "\(count) \(noun)   ·   \(flagText)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Time Entries")
                .font(.headline)
            Text("Tap + to log your first one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The name of whichever Task/Project/Client/Course `entry` is attached
    /// to, looked up from the view model's already-loaded picker data —
    /// falls back to a placeholder rather than crashing if the referenced
    /// item isn't in the loaded lists (e.g. deleted between loads).
    private func containerLabel(for entry: TimeEntry) -> String {
        if let taskID = entry.taskID {
            return viewModel.tasks.first { $0.id == taskID }?.title ?? "Unknown Task"
        }
        if let projectID = entry.projectID {
            return viewModel.projects.first { $0.id == projectID }?.name ?? "Unknown Project"
        }
        if let clientID = entry.clientID {
            return viewModel.clients.first { $0.id == clientID }?.name ?? "Unknown Client"
        }
        if let courseID = entry.courseID {
            return viewModel.courses.first { $0.id == courseID }?.name ?? "Unknown Course"
        }
        return "Unattached"
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
