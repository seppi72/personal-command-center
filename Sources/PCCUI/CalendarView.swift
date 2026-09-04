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
///
/// On the shared Liquid Glass system since issue #71 — full-width
/// `GlassBubble` rows on `GlassScreenBackground()`, replacing the earlier
/// Solari departures-board costume (a chrome-yellow instrument panel, and a
/// split-flap tile for every date) `git log` on this file still shows. The
/// split-flap device is deleted outright rather than redrawn in glass — a
/// date doesn't need a prop to read as a date — and every date now just sets
/// in this chassis's rounded font face instead.
public struct CalendarView: View {
    @ObservedObject private var viewModel: CalendarViewModel

    public init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CalendarContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `CalendarView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct CalendarContent: View {
    @ObservedObject var viewModel: CalendarViewModel
    @State private var isPresentingNewCommitmentSheet = false
    @State private var editingCommitment: PersonalCommitment?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.entries.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    entryScroll
                }
            }
            .background(GlassScreenBackground())
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

    /// A `ScrollView` of glass rows rather than a `List` — this screen's
    /// whole point is liquid glass floating on plain white/black, which
    /// needs each row to draw its own translucent Material-backed shape
    /// (the shared `GlassBubble`) rather than a native list container's
    /// opaque row fill (mirrors `DeadlinesView`'s own move from `List` to
    /// `ScrollView` + custom bubbles for the same reason). Deletion moves
    /// from the old `List`'s swipe gesture onto each editable row's own
    /// context menu — a `ScrollView` has no `List`-style swipe gesture to
    /// give it for free (mirrors `CategoriesView`'s identical grid-to-card
    /// tradeoff).
    private var entryScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                VStack(spacing: 14) {
                    ForEach(viewModel.entries) { entry in
                        row(for: entry)
                    }
                }
                .padding(.top, 18)
            }
            .padding(PCCChassis.outerMargin)
        }
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
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
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

    // MARK: - Rows

    @ViewBuilder
    private func row(for entry: CalendarEntry) -> some View {
        switch entry {
        case .commitment(let commitment):
            CalendarEntryBubble(entry: entry, commitment: commitment, onTap: { editingCommitment = commitment })
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteCommitment(commitment) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        case .mirroredEvent:
            // No `onTap`, and no context menu: a mirrored event is
            // read-only through the Command Center (spec #1, user story
            // 22) — nothing to tap into or delete.
            CalendarEntryBubble(entry: entry, commitment: nil, onTap: nil)
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
}

// MARK: - Calendar entry bubble

/// One row: the shared `GlassBubble` surface (`.fullWidth` size) with this
/// screen's own content on it — a leading date, the title, and a trailing
/// badge — shared by both an editable Commitment and a read-only mirrored
/// event so the two line up visually and differ only in that badge (a
/// `SyncStatusBadge` for a Commitment, a lock glyph for a mirrored event)
/// and in whether `onTap` is set. The leading date sets in this chassis's
/// rounded font face rather than any bespoke device — see this file's own
/// doc comment. The bubble's material, tint, specular highlight and rim
/// come from `PCCChassis`, not from here; only the layout is this screen's.
private struct CalendarEntryBubble: View {
    let entry: CalendarEntry
    let commitment: PersonalCommitment?
    let onTap: (() -> Void)?

    private static let style: GlassBubbleStyle = .fullWidth
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { content }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
            } else {
                content
            }
        }
        .glassBubble(Self.style)
    }

    private var content: some View {
        HStack(spacing: 14) {
            Text(Self.dateFormatter.string(from: entry.startDate))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(entry.title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let commitment {
                SyncStatusBadge(syncStatus: commitment.syncStatus)
            } else {
                Label("Read-only", systemImage: "lock.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Read-only, mirrored from your external Calendar")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .foregroundStyle(entry.isEditable ? .primary : .secondary)
        // Without this, only the rendered text/badge actually registers a
        // tap — the `.frame(maxWidth: .infinity)` title above adds layout
        // width but no hit-testable area on its own (the same gap
        // `TaskBubble`'s own doc comment calls out for its row).
        .contentShape(Rectangle())
    }
}
