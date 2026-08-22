import SwiftUI

/// Minimal Mac/iOS screen for ticket #4: lists Tasks (optionally scoped to
/// one Project via `TasksViewModel`'s `scopedProjectID`), and supports
/// creating, editing, deleting, completing/uncompleting, and reassigning a
/// Task's Project. One shared SwiftUI view for both platforms — no
/// platform-specific chrome, per the ticket's "minimal" scope (mirrors
/// `ProjectsView`).
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
                    projects: viewModel.projects
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
                    projects: viewModel.projects
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
/// Task" — a title, optional notes, and a Project picker (mirrors
/// `ProjectFormSheet`).
struct TaskFormSheet: View {
    let title: String
    let projects: [Project]
    let onSave: (TaskFormValues) async -> Void

    @State private var taskTitle: String
    @State private var notes: String
    @State private var projectID: UUID?
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialTitle: String,
        initialNotes: String,
        initialProjectID: UUID?,
        projects: [Project],
        onSave: @escaping (TaskFormValues) async -> Void
    ) {
        self.title = title
        self.projects = projects
        self.onSave = onSave
        self._taskTitle = State(initialValue: initialTitle)
        self._notes = State(initialValue: initialNotes)
        self._projectID = State(initialValue: initialProjectID)
    }

    private var trimmedTitle: String {
        taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $taskTitle)
                TextField("Notes", text: $notes)
                Picker("Project", selection: $projectID) {
                    Text("None").tag(UUID?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(UUID?.some(project.id))
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
                        let values = TaskFormValues(title: trimmedTitle, notes: trimmedNotes, projectID: projectID)
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
