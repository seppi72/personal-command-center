import SwiftUI

/// Shared create/edit form: the same sheet serves "New Task" and "Edit
/// Task" — a title, optional notes, a Project *or* Course picker (never
/// both — ADR-0003), a Sprint picker scoped to the chosen Project (issue
/// #89), a Kind label (ticket #88) and a Deadline toggle (mirrors
/// `ProjectFormSheet`).
/// Its Section stays in the shared chassis look — a `Form`'s native
/// controls don't read as glass however they're dressed
/// (`AccountFormSheet`'s doc comment carries this reasoning in full) — but
/// its ground now repaints to `GlassScreenBackground()` via
/// `glassScreenBackground()`, per issue #68.
struct TaskFormSheet: View {
    let title: String
    let projects: [Project]
    let courses: [Course]
    /// Every Sprint the caller knows about, across every Project — narrowed
    /// to the currently-picked Project's own by `availableSprints`, since a
    /// Sprint can only group Tasks of the Project it belongs to
    /// (`TaskController.assignSprint`).
    let sprints: [Sprint]
    let onSave: (TaskFormValues) async -> Void

    @State private var taskTitle: String
    @State private var notes: String
    @State private var projectID: UUID?
    @State private var courseID: UUID?
    @State private var sprintID: UUID?
    @State private var kind: String
    @State private var hasDeadline: Bool
    @State private var dueDate: Date
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialTitle: String,
        initialNotes: String,
        initialProjectID: UUID?,
        initialCourseID: UUID?,
        initialSprintID: UUID? = nil,
        initialKind: String? = nil,
        initialDueDate: Date?,
        projects: [Project],
        courses: [Course],
        sprints: [Sprint] = [],
        onSave: @escaping (TaskFormValues) async -> Void
    ) {
        self.title = title
        self.projects = projects
        self.courses = courses
        self.sprints = sprints
        self.onSave = onSave
        self._taskTitle = State(initialValue: initialTitle)
        self._notes = State(initialValue: initialNotes)
        self._projectID = State(initialValue: initialProjectID)
        self._courseID = State(initialValue: initialCourseID)
        self._sprintID = State(initialValue: initialSprintID)
        self._kind = State(initialValue: initialKind ?? "")
        self._hasDeadline = State(initialValue: initialDueDate != nil)
        self._dueDate = State(initialValue: initialDueDate ?? Date())
    }

    private var trimmedTitle: String {
        taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` when left blank — a Task's Kind is optional (`CONTEXT.md`),
    /// and an empty string would read as the label "" rather than as no
    /// label at all.
    private var trimmedKind: String? {
        let trimmed = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The Sprints the Sprint picker offers — only those of the currently
    /// picked Project, and none at all when no Project is picked or that
    /// Project doesn't use Sprints, in which case the picker is hidden
    /// rather than shown empty.
    private var availableSprints: [Sprint] {
        guard let projectID else { return [] }
        return sprints.filter { $0.projectID == projectID }.sorted { $0.startDate < $1.startDate }
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
                    TextField("Title", text: $taskTitle)
                        .pccField()
                    TextField("Notes", text: $notes)
                        .pccField()
                    // Free text rather than a picker: Kind is an open
                    // vocabulary — homework, study, reading and the like
                    // (`CONTEXT.md`) — with no fixed list to choose from.
                    TextField("Kind", text: $kind)
                        .pccField()
                    // A Task belongs to at most one of {Project, Course}
                    // (ADR-0003) — picking one clears the other rather than
                    // leaving both pickers free to disagree.
                    PCCMenuPicker(
                        "Project", selection: $projectID,
                        options: [(UUID?.none, "None")] + projects.map { (Optional($0.id), $0.name) }
                    )
                    .onChange(of: projectID) { newValue in
                        if newValue != nil { courseID = nil }
                        // A Sprint belongs to one Project for its lifetime
                        // (`CONTEXT.md`), so a Project change can't carry
                        // the old Project's Sprint along with it.
                        sprintID = nil
                    }
                    if !availableSprints.isEmpty {
                        PCCMenuPicker(
                            "Sprint", selection: $sprintID,
                            options: [(UUID?.none, "None")] + availableSprints.map { (Optional($0.id), $0.name) }
                        )
                    }
                    PCCMenuPicker(
                        "Course", selection: $courseID,
                        options: [(UUID?.none, "None")] + courses.map { (Optional($0.id), $0.name) }
                    )
                    .onChange(of: courseID) { newValue in
                        if newValue != nil { projectID = nil }
                    }
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
                        let values = TaskFormValues(
                            title: trimmedTitle,
                            notes: trimmedNotes,
                            projectID: projectID,
                            courseID: courseID,
                            sprintID: sprintID,
                            dueDate: selectedDueDate,
                            kind: trimmedKind
                        )
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }
}
