import SwiftUI

/// Minimal Mac/iOS screen for ticket #8: recent `AutomationLog` entries
/// (`CONTEXT.md`) — what the system has done on its own, e.g. a CalDAV push
/// or Calendar pull — with the most recent sync failure, if any, surfaced as
/// a banner up top rather than left to be spotted by scrolling (this
/// ticket's "surfaced clearly... rather than failing silently" AC). One
/// shared SwiftUI view for both platforms — no platform-specific chrome, per
/// this repo's established "minimal" scope for these screens (mirrors
/// `DeadlinesView`). Read-only: nothing here is owner-editable.
public struct AutomationLogView: View {
    @ObservedObject private var viewModel: AutomationLogViewModel

    public init(viewModel: AutomationLogViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.entries.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    entryList
                }
            }
            .navigationTitle("Automation Log")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    private var entryList: some View {
        List {
            if let mostRecentFailure = viewModel.mostRecentFailure {
                Section {
                    failureBanner(mostRecentFailure)
                }
            }
            Section("Recent Activity") {
                ForEach(viewModel.entries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    /// The "surfaced clearly" element this ticket asks for: unmissable at
    /// the top of the screen, distinct from an ordinary row, regardless of
    /// whether the failure itself is still recent enough to also appear in
    /// `entries` below.
    private func failureBanner(_ entry: AutomationLogEntry) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Most recent sync failure")
                    .font(.headline)
                Text(entry.detail)
                    .font(.subheadline)
                Text(entry.occurredAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func row(for entry: AutomationLogEntry) -> some View {
        HStack(alignment: .top) {
            outcomeIcon(for: entry.outcome)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.actionType)
                Text(entry.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.occurredAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func outcomeIcon(for outcome: AutomationLogEntry.Outcome) -> some View {
        switch outcome {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Automation Activity Yet")
                .font(.headline)
            Text("Actions the system takes on its own, like a Calendar sync, will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
