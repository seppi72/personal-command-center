import SwiftUI

/// Ticket #25: the Work Hours rollup screen — a `Picker` for which of the
/// five dimensions to group by, two `DatePicker`s for the range, and a
/// plain `List` of `{name, total}` rows for the result. No chart, matching
/// every other `PCCUI` screen's minimal convention (`TimeEntriesView`,
/// `TasksView`, etc.) — this ticket's own settled scope. One shared SwiftUI
/// view for both platforms, no platform-specific chrome.
public struct WorkHoursView: View {
    @ObservedObject private var viewModel: WorkHoursViewModel

    public init(viewModel: WorkHoursViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        WorkHoursContent(viewModel: viewModel)
            .screenTheme(.greenLedger)
    }
}

/// The screen's actual content — split out from `WorkHoursView` itself so
/// `.screenTheme(.greenLedger)` (applied in that struct's body, above) is
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
                controls
                    .padding(.horizontal, PCCChassis.outerMargin)
                    .padding(.top, PCCChassis.outerMargin)
                totalLine
                    .padding(.horizontal, PCCChassis.outerMargin)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                if viewModel.rows.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    rowList
                }
            }
            .background(PanelBackground())
            .navigationTitle("Work Hours")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    // MARK: - Total line

    /// This screen's signature: a boxed, double-ruled grand total — the
    /// bottom line of a real accounting ledger — in place of the shared
    /// chassis's plain mono readout strip every other screen's hero number
    /// uses.
    private var totalLine: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Total")
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
            Text(Self.formattedDuration(totalSeconds))
                .font(.pccReadout(22))
                .foregroundStyle(theme.accent(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.panelSurface(colorScheme))
        .overlay(
            Rectangle().fill(theme.accent(colorScheme)).frame(height: 2),
            alignment: .top
        )
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Rectangle().fill(theme.accent(colorScheme)).frame(height: 1.5)
                Rectangle().fill(theme.accent(colorScheme)).frame(height: 1.5)
            }
        }
    }

    private var totalSeconds: Double {
        viewModel.rows.reduce(0) { $0 + $1.totalSeconds }
    }

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

    /// Alternating "green-bar" row stripes — classic tractor-feed
    /// accounting paper — rather than the shared chassis's per-row bordered
    /// cards (`panelRows()`); a faint accent-tinted wash over every other
    /// row instead of a dedicated theme color, since `ScreenTheme` has no
    /// field of its own for a striping color and this is the only screen
    /// that wants one.
    private var rowList: some View {
        List(Array(viewModel.rows.enumerated()), id: \.offset) { index, row in
            HStack {
                Text(Self.label(for: row))
                Spacer()
                Text(Self.formattedDuration(row.totalSeconds))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .listRowBackground(rowBackground(index: index))
            .listRowSeparatorTint(theme.panelLine(colorScheme))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func rowBackground(index: Int) -> some View {
        ZStack {
            theme.panelSurface(colorScheme)
            if index % 2 == 1 {
                theme.accent(colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.10)
            }
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

    /// "1h 30m" / "45m" — whole minutes only, matching every other
    /// `PCCUI` screen's plain-text, no-chart convention rather than adding
    /// a `DateComponentsFormatter` dependency for one label.
    private static func formattedDuration(_ totalSeconds: Double) -> String {
        let totalMinutes = Int(totalSeconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Green Ledger theme

extension ScreenTheme {
    /// `WorkHoursView`'s own vibe: a green-bar accounting ledger — pale
    /// mint-and-white striped paper in Light Mode, a green-phosphor
    /// accounting-terminal read of the same numbers in Dark Mode (glowing
    /// after hours rather than printed on stock). Signal colors left as
    /// `ScreenTheme.default`'s.
    fileprivate static let greenLedger = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x10201A) : Color(hex: 0xF4F5EF) },
        panelSurface: { $0 == .dark ? Color(hex: 0x17251D) : Color(hex: 0xFFFFFF) },
        panelLine: { $0 == .dark ? Color(hex: 0x2C4536) : Color(hex: 0xC4D1C0) },
        accent: { $0 == .dark ? Color(hex: 0x7FE0A0) : Color(hex: 0x2E5C3E) },
        signalGreen: ScreenTheme.default.signalGreen,
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: ScreenTheme.default.signalRed
    )
}
