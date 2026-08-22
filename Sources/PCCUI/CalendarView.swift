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
            .alert("Error", isPresented: isShowingError, presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $isPresentingNewCommitmentSheet) {
                PersonalCommitmentFormSheet(title: "New Commitment", initialValues: nil) { values in
                    await viewModel.createCommitment(values)
                }
            }
            .sheet(item: $editingCommitment) { commitment in
                PersonalCommitmentFormSheet(
                    title: "Edit Commitment",
                    initialValues: PersonalCommitmentFormValues(
                        title: commitment.title,
                        startDate: commitment.startDate,
                        endDate: commitment.endDate,
                        recurrenceRule: commitment.recurrenceRule
                    )
                ) { values in
                    await viewModel.updateCommitment(commitment, with: values)
                }
            }
        }
    }

    private var entryList: some View {
        List {
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
        }
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
    /// the trailing badge — the sync-status badge from
    /// `PersonalCommitmentsView` for a Commitment, a lock glyph for a
    /// mirrored event.
    private func rowContent(for entry: CalendarEntry, commitment: PersonalCommitment?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.title)
                Spacer()
                if let commitment {
                    syncStatusBadge(for: commitment.syncStatus)
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

    /// Same badge as `PersonalCommitmentsView.syncStatusBadge` — kept as a
    /// private copy rather than shared, since factoring out one two-line
    /// `switch` isn't worth a new file, and the two views may still diverge
    /// on this later (e.g. text vs. icon-only) without a cross-file coupling
    /// to manage.
    @ViewBuilder
    private func syncStatusBadge(for syncStatus: PersonalCommitment.SyncStatus) -> some View {
        switch syncStatus {
        case .synced:
            EmptyView()
        case .failed:
            Label("Sync failed", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        case .pending:
            Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
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

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { viewModel.errorMessage = nil } }
        )
    }
}
