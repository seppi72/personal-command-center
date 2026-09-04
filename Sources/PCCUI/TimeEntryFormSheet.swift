import SwiftUI

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
