import SwiftUI

/// Minimal Mac/iOS screen for ticket #3: lists Projects, and supports
/// creating, editing (renaming), and deleting one. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope.
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
                ProjectFormSheet(title: "New Project", initialName: "") { name in
                    await viewModel.createProject(name: name)
                }
            }
            .sheet(item: $editingProject) { project in
                ProjectFormSheet(title: "Edit Project", initialName: project.name) { name in
                    await viewModel.renameProject(project, to: name)
                }
            }
        }
    }

    private var projectList: some View {
        List {
            ForEach(viewModel.projects) { project in
                Button(project.name) {
                    editingProject = project
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
/// Project" since both are just a name field with a save action.
struct ProjectFormSheet: View {
    let title: String
    let onSave: (String) async -> Void

    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String, onSave: @escaping (String) async -> Void) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = trimmedName
                        Task {
                            await onSave(name)
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}
