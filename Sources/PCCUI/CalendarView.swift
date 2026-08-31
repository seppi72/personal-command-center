import SwiftUI

/// The combined Calendar screen (ticket #7): owner-created Personal
/// Commitments and read-only mirrored external Calendar events in one
/// chronological list, visually distinguished (spec #1, user story 22) —
/// a mirrored row shows a lock glyph and muted styling and isn't tappable;
/// a Commitment row keeps `PersonalCommitmentsView`'s tap-to-edit and
/// sync-status badge. One shared SwiftUI view for both platforms — no
/// platform-specific chrome, per this repo's established "minimal" scope
/// for these screens (mirrors `PersonalCommitmentsView`/`DeadlinesView`).
///
/// This doesn't replace `PersonalCommitmentsView` — that screen still owns
/// Commitment-only browsing/editing. This one is the "everything on my
/// calendar, at a glance" view spec #1 asks for on top of it.
public struct CalendarView: View {
    @ObservedObject private var viewModel: CalendarViewModel
    @State private var isPresentingNewCommitmentSheet = false
    @State private var editingCommitment: PersonalCommitment?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    public init(viewModel: CalendarViewModel) {
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
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewCommitmentSheet = true
                    } label: {
                        Label("Add Commitment", systemImage: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
            .commitmentEditingSheets(
                isPresentingNewCommitmentSheet: $isPresentingNewCommitmentSheet,
                editingCommitment: $editingCommitment,
                courses: viewModel.courses,
                onCreate: { values in await viewModel.createCommitment(values) },
                onUpdate: { commitment, values in await viewModel.updateCommitment(commitment, with: values) }
            )
        }
    }

    private var entryList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.entries) { entry in
                    row(for: entry)
                }
                .onDelete { offsets in
                    let toDelete = offsets.compactMap { offset -> PersonalCommitment? in
                        guard case let .commitment(commitment) = viewModel.entries[offset] else { return nil }
                        return commitment
                    }
                    Task {
                        for commitment in toDelete {
                            await viewModel.deleteCommitment(commitment)
                        }
                    }
                }
                .panelRows()
            }
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

    private var failedSyncCount: Int {
        viewModel.entries.filter {
            if case let .commitment(commitment) = $0 { return commitment.syncStatus == .failed }
            return false
        }.count
    }

    private var todayCount: Int {
        viewModel.entries.filter { Calendar.current.isDateInToday($0.startDate) }.count
    }

    private var overallStatus: PanelStatus {
        if failedSyncCount > 0 { return .critical }
        return todayCount > 0 ? .attention : .nominal
    }

    private var statusStripText: String {
        let count = viewModel.entries.count
        let noun = count == 1 ? "ENTRY" : "ENTRIES"
        if failedSyncCount > 0 {
            return "\(count) \(noun)   ·   \(failedSyncCount) SYNC FAILED"
        }
        return "\(count) \(noun)   ·   \(todayCount) TODAY"
    }

    @ViewBuilder
    private func row(for entry: CalendarEntry) -> some View {
        switch entry {
        case .commitment(let commitment):
            Button {
                editingCommitment = commitment
            } label: {
                rowContent(for: entry, commitment: commitment)
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
        case .mirroredEvent:
            // Not a Button: a mirrored event is read-only through the
            // Command Center (spec #1, user story 22) — nothing to tap
            // into.
            rowContent(for: entry, commitment: nil)
        }
    }

    /// One row's content, shared by both cases so an editable Commitment
    /// and a read-only mirrored event line up visually and differ only in
    /// the trailing badge — a `SyncStatusBadge` for a Commitment, a lock
    /// glyph for a mirrored event.
    private func rowContent(for entry: CalendarEntry, commitment: PersonalCommitment?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.title)
                Spacer()
                if let commitment {
                    SyncStatusBadge(syncStatus: commitment.syncStatus)
                } else {
                    Label("Read-only", systemImage: "lock.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Read-only, mirrored from your external Calendar")
                }
            }
            Text(entry.startDate, style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(entry.isEditable ? .primary : .secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing on your Calendar")
                .font(.headline)
            Text("Tap + to schedule a Personal Commitment, or wait for the next Calendar sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
