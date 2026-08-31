import SwiftUI

/// Minimal Mac/iOS screen for ticket #5: the Deadline-proximity-sorted view
/// of every Task and Project together, with undated items still shown. One
/// shared SwiftUI view for both platforms — no platform-specific chrome, per
/// the ticket's "minimal" scope (mirrors `ProjectsView`/`TasksView`).
/// Read-only — set/clear a Deadline from the Tasks or Projects screen.
public struct DeadlinesView: View {
    @ObservedObject private var viewModel: DeadlinesViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

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
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.items) { item in
                    HStack {
                        Image(systemName: Self.symbolName(for: item.kind))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .strikethrough(item.isComplete == true)
                            if let dueDate = item.dueDate {
                                Text(dueDate, style: .date)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Self.isOverdue(item) ? theme.signalRed(colorScheme) : .secondary)
                            } else {
                                Text("No date")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .panelRows()
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

    private var overallStatus: PanelStatus {
        overdueCount > 0 ? .critical : .nominal
    }

    private var overdueCount: Int {
        viewModel.items.filter(Self.isOverdue).count
    }

    private static func isOverdue(_ item: DeadlineItem) -> Bool {
        guard let dueDate = item.dueDate, item.isComplete != true else { return false }
        return dueDate < Date()
    }

    private var statusStripText: String {
        let count = viewModel.items.count
        let noun = count == 1 ? "DEADLINE" : "DEADLINES"
        let flagText = overdueCount > 0 ? "\(overdueCount) OVERDUE" : "ALL CLEAR"
        return "\(count) \(noun)   ·   \(flagText)"
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

    /// Each `DeadlineItem.Kind`'s row glyph — a Course reuses neither the
    /// Task nor the Project glyph, since it's a third, distinct kind of
    /// container (ticket #20).
    private static func symbolName(for kind: DeadlineItem.Kind) -> String {
        switch kind {
        case .task: return "checkmark.circle"
        case .project: return "folder"
        case .course: return "graduationcap"
        }
    }
}
