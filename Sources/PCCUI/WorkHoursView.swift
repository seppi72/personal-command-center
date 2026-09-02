import SwiftUI

/// Ticket #25: the Work Hours rollup screen — a `Picker` for which of the
/// five dimensions to group by, two `DatePicker`s for the range, and a
/// row of `{name, total}` figures for the result. No chart, matching every
/// other `PCCUI` screen's minimal convention (`TimeEntriesView`,
/// `TasksView`, etc.) — this ticket's own settled scope. One shared SwiftUI
/// view for both platforms, no platform-specific chrome.
///
/// On the shared Liquid Glass system since issue #67 — full-width
/// `GlassBubble` rows on `GlassScreenBackground()`, replacing the earlier
/// green-bar ledger costume (alternating row stripes, the boxed double-ruled
/// total line) `git log` on this file still shows.
public struct WorkHoursView: View {
    @ObservedObject private var viewModel: WorkHoursViewModel

    public init(viewModel: WorkHoursViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        WorkHoursContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `WorkHoursView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct WorkHoursContent: View {
    @ObservedObject var viewModel: WorkHoursViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusStrip
                    .padding(.horizontal, PCCChassis.outerMargin)
                    .padding(.top, PCCChassis.outerMargin)
                controls
                    .padding(.horizontal, PCCChassis.outerMargin)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                if viewModel.rows.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    rowScroll
                }
            }
            .background(GlassScreenBackground())
            .navigationTitle("Work Hours")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    // MARK: - Status strip

    /// `.idle` — like `CategoriesView`'s own roster, a Work Hours rollup has
    /// no urgency signal of its own to flag (a total is never "bad" the way
    /// a negative balance is); kept for layout consistency and to carry the
    /// grand total, which the deleted boxed double-ruled `totalLine` used to
    /// own on its own.
    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(.idle)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
            Text(Self.formattedDuration(totalSeconds))
                .font(.pccReadout(14, weight: .semibold))
                .foregroundStyle(theme.accent(colorScheme))
        }
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var totalSeconds: Double {
        viewModel.rows.reduce(0) { $0 + $1.totalSeconds }
    }

    private var statusStripText: String {
        let count = viewModel.rows.count
        let noun = count == 1 ? "ROW" : "ROWS"
        return "\(count) \(noun)"
    }

    // MARK: - Controls

    /// A compact filter bar — reloads on every control change rather than
    /// needing an explicit "Apply" button, since a Work Hours rollup is
    /// cheap to recompute and has no unsaved-state concept the way
    /// `TimeEntryFormSheet` does.
    private var controls: some View {
        HStack(spacing: 10) {
            PCCMenuPicker(
                "Group by",
                selection: $viewModel.groupBy,
                options: WorkHoursGroupBy.allCases.map { ($0, $0.displayName) },
                style: .boxed
            )
            .onChange(of: viewModel.groupBy) { _ in
                Task { await viewModel.load() }
            }
            PCCDateRangeControl(selection: $viewModel.dateRange) {
                Task { await viewModel.load() }
            }
            Spacer()
        }
    }

    // MARK: - Rows

    /// A `ScrollView` of `WorkHoursRowBubble`s — each row draws the shared
    /// `GlassBubble` surface rather than a `List`'s opaque native row chrome
    /// (mirrors `AccountsView`'s own move from `List` to `ScrollView` +
    /// custom cards for the same reason). Replaces the prior alternating
    /// "green-bar" row stripes with plain full-width bubbles — no signature
    /// device left here, per issue #67; the numbers are the content.
    private var rowScroll: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(Array(viewModel.rows.enumerated()), id: \.offset) { _, row in
                    WorkHoursRowBubble(row: row)
                }
            }
            .padding(.horizontal, PCCChassis.outerMargin)
            .padding(.bottom, PCCChassis.outerMargin)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Work Hours")
                .font(.headline)
            Text("Nothing logged for this range yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "1h 30m" / "45m" — whole minutes only, matching every other
    /// `PCCUI` screen's plain-text, no-chart convention rather than adding
    /// a `DateComponentsFormatter` dependency for one label. `fileprivate`
    /// rather than the more usual per-bubble `private static func`
    /// (`TransactionBubble.formattedAmount`'s own convention): both
    /// `statusStrip`'s grand total and every `WorkHoursRowBubble`'s own
    /// figure need the identical formatting, so this lives once on the type
    /// that owns the strip rather than being duplicated onto the bubble too.
    fileprivate static func formattedDuration(_ totalSeconds: Double) -> String {
        let totalMinutes = Int(totalSeconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Work Hours row bubble

/// One rollup row: the shared `GlassBubble` surface (`.fullWidth` size) with
/// this screen's own content on it — the row's label (a day, or a
/// Project/Client/Task/Course name) and its total as the hero figure, in
/// monospaced tabular digits so totals compare down the column. Unlike
/// `TransactionBubble`'s signed amount, a duration has no sign to color by,
/// so the figure stays in the theme's plain accent rather than a
/// signal color.
private struct WorkHoursRowBubble: View {
    let row: WorkHoursRow

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        HStack(spacing: 16) {
            Text(Self.label(for: row))
                .font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 0)
            Text(WorkHoursContent.formattedDuration(row.totalSeconds))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.accent(colorScheme))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .glassBubble(Self.style)
    }

    /// A `day` row's `date` is set (`name`/`id` both `nil`); every other
    /// `groupBy`'s row has `name` set instead (`WorkHoursRow`'s own doc
    /// comment) — whichever is present is what this row's label shows.
    private static func label(for row: WorkHoursRow) -> String {
        if let date = row.date {
            return dayFormatter.string(from: date)
        }
        return row.name ?? "Unknown"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
