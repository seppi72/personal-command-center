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
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider()
                if viewModel.rows.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    rowList
                }
            }
            .background(GlassBackground())
            .navigationTitle("Work Hours")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
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
        .padding(12)
    }

    private var rowList: some View {
        List(Array(viewModel.rows.enumerated()), id: \.offset) { _, row in
            HStack {
                Text(Self.label(for: row))
                Spacer()
                Text(Self.formattedDuration(row.totalSeconds))
                    .foregroundStyle(.secondary)
            }
        }
        .glassRows()
        .scrollContentBackground(.hidden)
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
