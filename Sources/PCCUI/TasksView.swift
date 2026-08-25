import SwiftUI

/// Minimal Mac/iOS screen for ticket #4: lists Tasks (optionally scoped to
/// one Project via `TasksViewModel`'s `scopedProjectID`), and supports
/// creating, editing, deleting, completing/uncompleting, reassigning a
/// Task's Project, and setting/clearing its Deadline (ticket #5). One shared
/// SwiftUI view for both platforms — no platform-specific chrome, per the
/// ticket's "minimal" scope (mirrors `ProjectsView`).
public struct TasksView: View {
    @ObservedObject private var viewModel: TasksViewModel
    @State private var isPresentingNewTaskSheet = false
    @State private var editingTask: PCCTask?

    public init(viewModel: TasksViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.tasks.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewTaskSheet = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
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
            .sheet(isPresented: $isPresentingNewTaskSheet) {
                TaskFormSheet(
                    title: "New Task",
                    initialTitle: "",
                    initialNotes: "",
                    initialProjectID: nil,
                    initialCourseID: nil,
                    initialDueDate: nil,
                    projects: viewModel.projects,
                    courses: viewModel.courses
                ) { values in
                    await viewModel.createTask(values)
                }
            }
            .sheet(item: $editingTask) { task in
                TaskFormSheet(
                    title: "Edit Task",
                    initialTitle: task.title,
                    initialNotes: task.notes ?? "",
                    initialProjectID: task.projectID,
                    initialCourseID: task.courseID,
                    initialDueDate: task.dueDate,
                    projects: viewModel.projects,
                    courses: viewModel.courses
                ) { values in
                    await viewModel.updateTask(task, with: values)
                }
            }
        }
    }

    private var taskList: some View {
        List {
            ForEach(viewModel.tasks) { task in
                HStack {
                    Button {
                        Task {
                            await viewModel.setCompletion(task, isComplete: !task.isComplete)
                        }
                    } label: {
                        Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif

                    Button {
                        editingTask = task
                    } label: {
                        VStack(alignment: .leading) {
                            Text(task.title)
                                .strikethrough(task.isComplete)
                            if let notes = task.notes {
                                Text(notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let dueDate = task.dueDate {
                                Text(dueDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .onDelete { offsets in
                let toDelete = offsets.map { viewModel.tasks[$0] }
                Task {
                    for task in toDelete {
                        await viewModel.deleteTask(task)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Tasks")
                .font(.headline)
            Text("Tap + to create your first Task.")
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

/// Shared create/edit form: the same sheet serves "New Task" and "Edit
/// Task" — a title, optional notes, a Project *or* Course picker (never
/// both — ADR-0003), and a Deadline toggle (mirrors `ProjectFormSheet`).
struct TaskFormSheet: View {
    let title: String
    let projects: [Project]
    let courses: [Course]
    let onSave: (TaskFormValues) async -> Void

    @State private var taskTitle: String
    @State private var notes: String
    @State private var projectID: UUID?
    @State private var courseID: UUID?
    @State private var hasDeadline: Bool
    @State private var dueDate: Date
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialTitle: String,
        initialNotes: String,
        initialProjectID: UUID?,
        initialCourseID: UUID?,
        initialDueDate: Date?,
        projects: [Project],
        courses: [Course],
        onSave: @escaping (TaskFormValues) async -> Void
    ) {
        self.title = title
        self.projects = projects
        self.courses = courses
        self.onSave = onSave
        self._taskTitle = State(initialValue: initialTitle)
        self._notes = State(initialValue: initialNotes)
        self._projectID = State(initialValue: initialProjectID)
        self._courseID = State(initialValue: initialCourseID)
        self._hasDeadline = State(initialValue: initialDueDate != nil)
        self._dueDate = State(initialValue: initialDueDate ?? Date())
    }

    private var trimmedTitle: String {
        taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `nil` unless the "Has deadline" toggle is on — SwiftUI's `DatePicker`
    /// has no built-in optional-date mode, so the toggle stands in for one.
    private var selectedDueDate: Date? {
        hasDeadline ? dueDate : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $taskTitle)
                TextField("Notes", text: $notes)
                // A Task belongs to at most one of {Project, Course}
                // (ADR-0003) — picking one clears the other rather than
                // leaving both pickers free to disagree.
                Picker("Project", selection: $projectID) {
                    Text("None").tag(UUID?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(UUID?.some(project.id))
                    }
                }
                .onChange(of: projectID) { newValue in
                    if newValue != nil { courseID = nil }
                }
                Picker("Course", selection: $courseID) {
                    Text("None").tag(UUID?.none)
                    ForEach(courses) { course in
                        Text(course.name).tag(UUID?.some(course.id))
                    }
                }
                .onChange(of: courseID) { newValue in
                    if newValue != nil { projectID = nil }
                }
                Section("Deadline") {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
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
                            dueDate: selectedDueDate
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
