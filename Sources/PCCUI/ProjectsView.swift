import SwiftUI

/// Minimal Mac/iOS screen for ticket #3: lists Projects, and supports
/// creating, editing (renaming, setting/clearing a Deadline — ticket #5),
/// and deleting one. One shared SwiftUI view for both platforms — no
/// platform-specific chrome, per the ticket's "minimal" scope.
public struct ProjectsView: View {
    @ObservedObject private var viewModel: ProjectsViewModel
    @State private var isPresentingNewProjectSheet = false
    @State private var editingProject: Project?

    public init(viewModel: ProjectsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
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
            .sheet(item: $editingProject) { project in
                ProjectFormSheet(
                    title: "Edit Project",
                    initialName: project.name,
                    initialDueDate: project.dueDate
                ) { values in
                    await viewModel.updateProject(project, with: values)
                }
            }
        }
    }

    private var projectList: some View {
        List {
            ForEach(viewModel.projects) { project in
                Button {
                    editingProject = project
                } label: {
                    VStack(alignment: .leading) {
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
                    }
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
            .onDelete { offsets in
                let toDelete = offsets.map { viewModel.projects[$0] }
                Task {
                    for project in toDelete {
                        await viewModel.deleteProject(project)
                    }
                }
            }
        }
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
                TextField("Name", text: $name)
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
