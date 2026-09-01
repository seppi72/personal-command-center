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

    public init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CalendarContent(viewModel: viewModel)
            .screenTheme(.departuresBoard)
    }
}

/// The screen's actual content — split out from `CalendarView` itself so
/// `.screenTheme(.departuresBoard)` (applied in that struct's body, above)
/// is genuinely in effect by the time this struct's own `body` reads
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
                    entryList
                }
            }
            .background(PanelBackground())
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
        .scrollContentBackground(.hidden)
        // Same edge-margin fix as `TasksView.taskList` — see that
        // property's own doc comment for why this has to pad the `List`
        // itself rather than each row.
        .padding(.horizontal, PCCChassis.outerMargin)
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
        HStack(spacing: 14) {
            SplitFlapDate(date: entry.startDate)
            Text(entry.title)
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
        .padding(.vertical, 6)
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

// MARK: - Departures Board theme

extension ScreenTheme {
    /// `CalendarView`'s own vibe: a Solari split-flap departures display.
    /// A chrome-yellow accent — colder and brighter than Finance's gold
    /// or Tasks' safety-orange, so the three don't blur together in the
    /// sidebar. Signal colors are left as `ScreenTheme.default`'s.
    fileprivate static let departuresBoard = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x0E0E0A) : Color(hex: 0xF3F1EA) },
        panelSurface: { $0 == .dark ? Color(hex: 0x1C1B14) : Color(hex: 0xFFFFFF) },
        panelLine: { $0 == .dark ? Color(hex: 0x38361F) : Color(hex: 0xDDD8C8) },
        accent: { $0 == .dark ? Color(hex: 0xF2C230) : Color(hex: 0xA9820A) },
        signalGreen: ScreenTheme.default.signalGreen,
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: ScreenTheme.default.signalRed
    )
}

// MARK: - Split-flap date

/// This screen's signature device: every date renders as a row of
/// individually tiled characters with a seam line through the middle —
/// the Solari-board convention every airport/train departures display
/// uses — instead of a plain date string.
private struct SplitFlapDate: View {
    let date: Date

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private var characters: [Character] {
        Array(Self.formatter.string(from: date).uppercased())
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                if character == " " {
                    Color.clear.frame(width: 6)
                } else {
                    tile(character)
                }
            }
        }
        // A fixed number of tile slots (the longest this format ever
        // produces, "MMM DD" = 6 characters) so every row's date column
        // lines up regardless of how many characters its own date
        // actually rendered — a 1-digit day would otherwise be a
        // narrower column than a 2-digit one.
        .frame(width: 6 * 18, alignment: .leading)
    }

    private func tile(_ character: Character) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(colorScheme == .dark ? Color(hex: 0x030302) : Color(hex: 0x14130D))
            Text(String(character))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.accent(colorScheme))
            // The flap seam — the horizontal split every physical
            // Solari-board character has across its middle.
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(height: 1)
        }
        .frame(width: 15, height: 22)
    }
}
