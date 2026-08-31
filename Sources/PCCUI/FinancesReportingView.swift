import Charts
import SwiftUI

/// Ticket #40: the Finances Reporting screen — Net Worth (current figure +
/// trend chart), one Account's Balance-over-time chart, an expense-per-day
/// chart across every Account, and one Account's Projected Balance shown as
/// a single computed figure (text), not a chart, per the ticket's own
/// settled scope. First use of SwiftUI's native `Charts` framework in
/// `PCCUI` — no third-party charting dependency, unlike every other screen's
/// plain-`List` convention (`WorkHoursView`'s own doc comment), since this
/// ticket's own AC calls for actual trend/history/expense charts rather than
/// rows of numbers.
///
/// Every `Section` header is a panel nameplate — a `StatusDot` plus an
/// uppercase tracked-out label, matching `OverviewView`'s panel headers —
/// and every chart is restyled to that same system's hairline-trace
/// language (dashed gridlines, monospaced axis labels, a gradient-filled
/// `AreaMark` under a thin `LineMark`) instead of `Charts`' default chrome.
public struct FinancesReportingView: View {
    @ObservedObject private var viewModel: FinancesReportingViewModel

    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: FinancesReportingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                rangeSection
                netWorthSection
                accountBalanceSection
                expensesSection
                projectedBalanceSection
            }
            .glassScreenBackground()
            .navigationTitle("Finances Reporting")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    private var readoutColor: Color {
        GlassStyle.signalCyan(for: colorScheme)
    }

    // MARK: - Panel header

    /// Mirrors `OverviewView`'s panel header — a `StatusDot` plus an
    /// uppercase tracked-out nameplate — reused here as every `Section`'s
    /// header instead of the plain system-styled `Section(String)` title.
    private func panelHeader(_ title: String, systemImage: String, status: PanelStatus) -> some View {
        HStack(spacing: 8) {
            StatusDot(status)
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(title)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Range

    /// One shared range for Net Worth trend, Account Balance history, and
    /// expense-per-day — reloads every affected section on change rather
    /// than needing a separate "Apply" step, the same immediate-reload
    /// convention `WorkHoursView`'s own `controls` uses.
    private var rangeSection: some View {
        Section {
            HStack {
                Text("Range")
                    .foregroundStyle(.secondary)
                Spacer()
                PCCDateRangeControl(selection: $viewModel.dateRange) {
                    Task { await reloadAll() }
                }
            }
        } header: {
            panelHeader("Range", systemImage: "calendar", status: .idle)
        }
        .glassRows()
    }

    // MARK: - Net Worth

    private var netWorthSection: some View {
        Section {
            HStack(alignment: .lastTextBaseline) {
                Text("Current")
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.currency(viewModel.currentNetWorth))
                    .font(.pccReadout(24))
                    .foregroundStyle(readoutColor)
            }
            .padding(.vertical, 4)
            if viewModel.netWorthTrend.isEmpty {
                emptyChartLabel
            } else {
                trendChart(viewModel.netWorthTrend, valueLabel: "Net Worth")
            }
        } header: {
            panelHeader("Net Worth", systemImage: "chart.line.uptrend.xyaxis", status: netWorthStatus)
        }
        .glassRows()
    }

    private var netWorthStatus: PanelStatus {
        viewModel.currentNetWorth < 0 ? .critical : .nominal
    }

    // MARK: - Account Balance

    private var accountBalanceSection: some View {
        Section {
            accountPicker
            if viewModel.accountBalanceHistory.isEmpty {
                emptyChartLabel
            } else {
                trendChart(viewModel.accountBalanceHistory, valueLabel: "Balance")
            }
        } header: {
            panelHeader("Account Balance", systemImage: "building.columns", status: accountBalanceStatus)
        }
        .glassRows()
    }

    private var accountBalanceStatus: PanelStatus {
        guard let latest = viewModel.accountBalanceHistory.last else { return .idle }
        return latest.value < 0 ? .critical : .nominal
    }

    /// Shared by `netWorthSection` and `accountBalanceSection` — one
    /// hairline-trace `LineMark`+`AreaMark` pair (dashed gridlines,
    /// monospaced axis labels) instead of `Charts`' default combo, matching
    /// `OverviewView.netTrendChart`'s own oscilloscope treatment.
    private func trendChart(_ points: [DailyFigure], valueLabel: String) -> some View {
        Chart(points) { point in
            AreaMark(x: .value("Date", point.date, unit: .day), y: .value(valueLabel, point.value))
                .foregroundStyle(
                    LinearGradient(
                        colors: [readoutColor.opacity(0.30), readoutColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", point.date, unit: .day), y: .value(valueLabel, point.value))
                .foregroundStyle(readoutColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(GlassStyle.panelLine(for: colorScheme))
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 160)
    }

    // MARK: - Expenses

    private var expensesSection: some View {
        Section {
            if viewModel.expensesPerDay.isEmpty {
                emptyChartLabel
            } else {
                expensesChart
            }
        } header: {
            panelHeader("Expenses per Day", systemImage: "arrow.down.circle", status: .idle)
        }
        .glassRows()
    }

    /// Bars in `signalRed` — expenses are an outflow, the same red this
    /// system's gauges (`OverviewView.gaugeRow`) already use for "Expense"
    /// — instead of `Charts`' default accent-color bars.
    private var expensesChart: some View {
        Chart(viewModel.expensesPerDay) { row in
            BarMark(x: .value("Date", row.date, unit: .day), y: .value("Expenses", row.totalExpenses))
                .foregroundStyle(GlassStyle.signalRed(for: colorScheme))
                .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(GlassStyle.panelLine(for: colorScheme))
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 160)
    }

    // MARK: - Projected Balance

    private var projectedBalanceSection: some View {
        Section {
            PCCMenuPicker(
                "Period",
                selection: $viewModel.projectedBalancePeriod,
                options: ProjectedBalancePeriod.allCases.map { ($0, $0.displayName) }
            )
            .onChange(of: viewModel.projectedBalancePeriod) { _ in
                Task { await viewModel.loadSelectedAccountFigures() }
            }
            if let projected = viewModel.projectedBalance {
                LabeledContent("Average Daily Net", value: Self.currency(projected.averageDailyNet))
                HStack {
                    Text("Projected Balance")
                    Spacer()
                    Text(Self.currency(projected.projectedBalance))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(projected.projectedBalance < 0 ? GlassStyle.signalRed(for: colorScheme) : GlassStyle.signalGreen(for: colorScheme))
                }
            } else {
                Text("No Account selected").foregroundStyle(.secondary)
            }
        } header: {
            panelHeader("Projected Balance", systemImage: "chart.bar.doc.horizontal", status: projectedBalanceStatus)
        }
        .glassRows()
    }

    private var projectedBalanceStatus: PanelStatus {
        guard let projected = viewModel.projectedBalance else { return .idle }
        return projected.projectedBalance < 0 ? .critical : .nominal
    }

    /// Shared by `accountBalanceSection` and, transitively,
    /// `projectedBalanceSection` — both read `viewModel.selectedAccountID`,
    /// so one picker drives both sections rather than each needing its own.
    private var accountPicker: some View {
        PCCMenuPicker(
            "Account",
            selection: $viewModel.selectedAccountID,
            options: viewModel.accounts.map { (Optional($0.id), $0.name) }
        )
        .onChange(of: viewModel.selectedAccountID) { _ in
            Task { await viewModel.loadSelectedAccountFigures() }
        }
    }

    private var emptyChartLabel: some View {
        Text("Nothing logged for this range yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func reloadAll() async {
        await viewModel.load()
    }

    private static func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: "PHP"))
    }
}
