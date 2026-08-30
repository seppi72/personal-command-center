import SwiftUI

/// The app's landing screen: a fixed, read-only glance at three things —
/// the active Timer, today's-and-overdue Deadlines, and the last week's
/// Transactions — each capped and each with a tappable header that hands
/// off to whichever full screen covers it. One shared SwiftUI view for both
/// platforms, no platform-specific chrome, per this package's existing
/// "minimal" scope (mirrors `DeadlinesView`/`TransactionsView`).
///
/// Purely a glance: no inline actions here (no stop-timer, no mark-done) —
/// acting on anything happens on the full screen a header hands off to.
///
/// `Screen` (the sidebar's navigation enum) lives in the `PCCDesktop`
/// executable target, not in this package, so this view can't reference it
/// directly — `PCCUI` has no dependency in that direction. Three explicit
/// closures keep this view decoupled from any particular host app's
/// navigation model, the same way every other `PCCUI` screen has no
/// awareness of the sidebar that hosts it.
public struct OverviewView: View {
    @ObservedObject private var viewModel: OverviewViewModel
    private let onTapTimer: () -> Void
    private let onTapDeadlines: () -> Void
    private let onTapTransactions: () -> Void

    public init(
        viewModel: OverviewViewModel,
        onTapTimer: @escaping () -> Void,
        onTapDeadlines: @escaping () -> Void,
        onTapTransactions: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onTapTimer = onTapTimer
        self.onTapDeadlines = onTapDeadlines
        self.onTapTransactions = onTapTransactions
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    timerContent
                } header: {
                    sectionHeader("Timer", action: onTapTimer)
                }
                Section {
                    deadlinesContent
                } header: {
                    sectionHeader("Deadlines", action: onTapDeadlines)
                }
                Section {
                    transactionsContent
                } header: {
                    sectionHeader("Transactions", action: onTapTransactions)
                }
            }
            .navigationTitle("Overview")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    /// A section header that's also a button — tapping the section title
    /// jumps to that section's full screen (the sidebar selection change
    /// happens in whichever closure was passed in).
    private func sectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    private var timerContent: some View {
        if let activeTimer = viewModel.activeTimer {
            VStack(alignment: .leading, spacing: 2) {
                Text(containerLabel(for: activeTimer))
                    .font(.headline)
                Text("Started \(activeTimer.startDate, style: .relative) ago")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No timer running")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var deadlinesContent: some View {
        if viewModel.upcomingDeadlines.isEmpty {
            Text("No deadlines due")
                .foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.upcomingDeadlines) { item in
                HStack {
                    Image(systemName: Self.symbolName(for: item.kind))
                        .foregroundStyle(.secondary)
                    Text(item.title)
                    Spacer()
                    if let dueDate = item.dueDate {
                        Text(dueDate, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if viewModel.additionalDeadlinesCount > 0 {
                moreRow(count: viewModel.additionalDeadlinesCount, action: onTapDeadlines)
            }
        }
    }

    @ViewBuilder
    private var transactionsContent: some View {
        if viewModel.recentTransactions.isEmpty {
            Text("No transactions this week")
                .foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.recentTransactions) { transaction in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountName(for: transaction))
                        Text(transaction.date, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Self.formattedAmount(transaction))
                        .foregroundStyle(transaction.type == .expense ? .red : .green)
                }
            }
            if viewModel.additionalTransactionsCount > 0 {
                moreRow(count: viewModel.additionalTransactionsCount, action: onTapTransactions)
            }
        }
    }

    private func moreRow(count: Int, action: @escaping () -> Void) -> some View {
        Button("+\(count) more", action: action)
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
            .foregroundStyle(.secondary)
    }

    /// The name of whichever Task/Project/Client/Course `entry` is attached
    /// to, looked up from the view model's already-loaded picker data —
    /// falls back to a placeholder rather than crashing if the referenced
    /// item isn't in the loaded lists. Mirrors `TimerView.containerLabel`.
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

    /// The name of whichever Account `transaction` is logged against, looked
    /// up from the view model's already-loaded picker data — mirrors
    /// `TransactionsView.accountName(for:)`.
    private func accountName(for transaction: Transaction) -> String {
        viewModel.accounts.first { $0.id == transaction.accountID }?.name ?? "Unknown Account"
    }

    /// Mirrors `TransactionsView.formattedAmount(_:)`.
    private static func formattedAmount(_ transaction: Transaction) -> String {
        let signed = transaction.type == .expense ? -transaction.amount : transaction.amount
        return signed.formatted(.currency(code: "USD").sign(strategy: .always()))
    }

    /// Mirrors `DeadlinesView.symbolName(for:)`.
    private static func symbolName(for kind: DeadlineItem.Kind) -> String {
        switch kind {
        case .task: return "checkmark.circle"
        case .project: return "folder"
        case .course: return "graduationcap"
        }
    }
}
