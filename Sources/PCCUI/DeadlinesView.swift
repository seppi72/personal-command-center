import SwiftUI

/// Minimal Mac/iOS screen for ticket #5: the Deadline-proximity-sorted view
/// of every Task and Project together, with undated items still shown. One
/// shared SwiftUI view for both platforms — no platform-specific chrome, per
/// the ticket's "minimal" scope (mirrors `ProjectsView`/`TasksView`).
/// Read-only — set/clear a Deadline from the Tasks or Projects screen.
public struct DeadlinesView: View {
    @ObservedObject private var viewModel: DeadlinesViewModel

    public init(viewModel: DeadlinesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    itemList
                }
            }
            .navigationTitle("Deadlines")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Error", isPresented: isShowingError, presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private var itemList: some View {
        List(viewModel.items) { item in
            HStack {
                Image(systemName: item.kind == .task ? "checkmark.circle" : "folder")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(item.title)
                        .strikethrough(item.isComplete == true)
                    if let dueDate = item.dueDate {
                        Text(dueDate, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No date")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Deadlines")
                .font(.headline)
            Text("Attach a due date to a Task or Project to see it here.")
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
