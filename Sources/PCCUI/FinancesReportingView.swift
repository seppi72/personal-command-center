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
///
/// On top of that base instrument-panel conversion, this screen carries a
/// finance-specific signature: a ticker-style headline strip (hero Net
/// Worth readout + a `DeltaBadge` showing signed change and percent over
/// the selected range, the same "number + colored delta" convention every
/// stock/banking ticker uses) and directional `signalGreen`/`signalRed`
/// trend-chart coloring instead of a flat, always-cyan trace — a chart that
/// went up is green, one that went down is red, never a neutral brand
/// color. Projected Balance's total is ruled off above it, the way a paper
/// ledger rules off a sum, instead of sitting at plain caption weight.
public struct FinancesReportingView: View {
    @ObservedObject private var viewModel: FinancesReportingViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    public init(viewModel: FinancesReportingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    tickerStrip
                }
                netWorthSection
                accountBalanceSection
                expensesSection
                projectedBalanceSection
            }
            .panelScreenBackground()
            .navigationTitle("Finances Reporting")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    private var readoutColor: Color {
        theme.accent(colorScheme)
    }

    // MARK: - Directional signal

    /// Whether a series rose, fell, or held flat between its first and last
    /// point — the one comparison every badge and chart color in this
    /// screen is derived from.
    private enum TrendDirection {
        case up, down, flat
    }

    private static func trendDirection(from points: [DailyFigure]) -> TrendDirection {
        guard points.count > 1, let first = points.first, let last = points.last else { return .flat }
        if last.value > first.value { return .up }
        if last.value < first.value { return .down }
        return .flat
    }

    /// Chart traces are never neutral — unlike `DeltaBadge`, `.flat` still
    /// reads as green here, since a flat trace isn't a loss.
    private func chartColor(for direction: TrendDirection) -> Color {
        direction == .down ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme)
    }

    /// The small "▲ +₱4,200.00 (+3.1%)" ticker-style readout next to Net
    /// Worth and Account Balance. `nil` when there's nothing meaningful to
    /// compare (0 or 1 points) — the badge is omitted rather than shown
    /// hollow.
    private func deltaBadge(for points: [DailyFigure]) -> DeltaBadge? {
        guard points.count > 1, let first = points.first, let last = points.last else { return nil }
        let amount = Self.signedCurrency(last.value - first.value)
        var text = amount
        if first.value != 0 {
            let percent = (last.value - first.value) / abs(first.value)
            let percentText = percent.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
            text += " (\(percentText))"
        }
        return DeltaBadge(direction: Self.trendDirection(from: points), text: text)
    }

    private static func signedCurrency(_ amount: Double) -> String {
        amount.formatted(.currency(code: "PHP").sign(strategy: .always()))
    }

    /// A stock-ticker-style change indicator — an up/down triangle plus
    /// signed currency and percent, colored `signalGreen`/`signalRed`, or a
    /// plain secondary label with no arrow when the range is flat.
    private struct DeltaBadge: View {
        let direction: TrendDirection
        let text: String

        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.screenTheme) private var theme

        var body: some View {
            HStack(spacing: 3) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 8, weight: .black))
                }
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(color)
        }

        private var symbolName: String? {
            switch direction {
            case .up: return "arrowtriangle.up.fill"
            case .down: return "arrowtriangle.down.fill"
            case .flat: return nil
            }
        }

        private var color: Color {
            switch direction {
            case .up: return theme.signalGreen(colorScheme)
            case .down: return theme.signalRed(colorScheme)
            case .flat: return .secondary
            }
        }
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

    // MARK: - Ticker strip

    /// The screen's thesis: the hero Net Worth figure plus its
    /// `DeltaBadge`, and the shared date range that drives Net Worth
    /// trend, Account Balance history, and expense-per-day. Reloads every
    /// affected section on change rather than needing a separate "Apply"
    /// step, the same immediate-reload convention `WorkHoursView`'s own
    /// `controls` uses. Full-bleed, no section chrome, bottom hairline —
    /// the same treatment other screens' `statusStrip` uses.
    private var readoutCluster: some View {
        HStack(spacing: 8) {
            StatusDot(netWorthStatus)
            Text(Self.currency(viewModel.currentNetWorth))
                .font(.pccReadout(24))
                .foregroundStyle(readoutColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            deltaBadge(for: viewModel.netWorthTrend)
        }
    }

    /// `ViewThatFits` rather than a single fixed `HStack`: the date-range
    /// control's label plus a multi-figure PHP readout can together exceed
    /// a phone-portrait row's width, so the strip drops to two lines
    /// instead of clipping.
    private var tickerStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                readoutCluster
                Spacer(minLength: 8)
                PCCDateRangeControl(selection: $viewModel.dateRange) {
                    Task { await reloadAll() }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                readoutCluster
                PCCDateRangeControl(selection: $viewModel.dateRange) {
                    Task { await reloadAll() }
                }
            }
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

    // MARK: - Net Worth

    private var netWorthSection: some View {
        Section {
            Group {
                if viewModel.netWorthTrend.isEmpty {
                    emptyChartLabel
                } else {
                    trendChart(viewModel.netWorthTrend, valueLabel: "Net Worth")
                }
            }
            .padding(.vertical, 10)
        } header: {
            panelHeader("Net Worth", systemImage: "chart.line.uptrend.xyaxis", status: netWorthStatus)
        }
        .panelRows()
    }

    private var netWorthStatus: PanelStatus {
        viewModel.currentNetWorth < 0 ? .critical : .nominal
    }

    // MARK: - Account Balance

    private var accountBalanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    accountPicker
                    deltaBadge(for: viewModel.accountBalanceHistory)
                }
                if viewModel.accountBalanceHistory.isEmpty {
                    emptyChartLabel
                } else {
                    trendChart(viewModel.accountBalanceHistory, valueLabel: "Balance")
                }
            }
            .padding(.vertical, 10)
        } header: {
            panelHeader("Account Balance", systemImage: "building.columns", status: accountBalanceStatus)
        }
        .panelRows()
    }

    private var accountBalanceStatus: PanelStatus {
        guard let latest = viewModel.accountBalanceHistory.last else { return .idle }
        return latest.value < 0 ? .critical : .nominal
    }

    /// Shared by `netWorthSection` and `accountBalanceSection` — one
    /// hairline-trace `LineMark`+`AreaMark` pair (dashed gridlines,
    /// monospaced axis labels) instead of `Charts`' default combo, matching
    /// `OverviewView.netTrendChart`'s own oscilloscope treatment. Colored
    /// `signalGreen`/`signalRed` by whether the range rose or fell — a
    /// trend chart that's always the same neutral color reads as
    /// decoration, not as an answer to "is this going the right way?".
    private func trendChart(_ points: [DailyFigure], valueLabel: String) -> some View {
        let color = chartColor(for: Self.trendDirection(from: points))
        return Chart(points) { point in
            AreaMark(x: .value("Date", point.date, unit: .day), y: .value(valueLabel, point.value))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.30), color.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", point.date, unit: .day), y: .value(valueLabel, point.value))
                .foregroundStyle(color)
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
                    .foregroundStyle(theme.panelLine(colorScheme))
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
            Group {
                if viewModel.expensesPerDay.isEmpty {
                    emptyChartLabel
                } else {
                    expensesChart
                }
            }
            .padding(.vertical, 10)
        } header: {
            panelHeader("Expenses per Day", systemImage: "arrow.down.circle", status: .idle)
        }
        .panelRows()
    }

    /// The period's average daily expense — a real budget-pace reference,
    /// not just a set of bars with no baseline to read them against.
    private var averageExpense: Double {
        let values = viewModel.expensesPerDay.map(\.totalExpenses)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    /// Bars in `signalRed` — expenses are an outflow, the same red this
    /// system's gauges (`OverviewView.gaugeRow`) already use for "Expense"
    /// — instead of `Charts`' default accent-color bars. A dashed
    /// `RuleMark` at the period average gives the bars something to be
    /// read against, the same way a real expense report shows a budget
    /// line.
    private var expensesChart: some View {
        Chart {
            ForEach(viewModel.expensesPerDay) { row in
                BarMark(x: .value("Date", row.date, unit: .day), y: .value("Expenses", row.totalExpenses))
                    .foregroundStyle(theme.signalRed(colorScheme))
                    .cornerRadius(2)
            }
            RuleMark(y: .value("Average", averageExpense))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(theme.panelLine(colorScheme))
                .annotation(position: .top, alignment: .trailing, spacing: 4) {
                    Text("AVG \(Self.currency(averageExpense))/day")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
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
                    .foregroundStyle(theme.panelLine(colorScheme))
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
            VStack(alignment: .leading, spacing: 8) {
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
                    // Ruled off above the total, the way a paper ledger rules
                    // off a sum — this is the screen's actual bottom line, so
                    // it gets the same hero readout weight as Net Worth rather
                    // than a plain caption.
                    Rectangle()
                        .fill(theme.panelLine(colorScheme))
                        .frame(height: 1)
                        .padding(.top, 4)
                    HStack(alignment: .lastTextBaseline) {
                        Text("Projected Balance")
                            .pccPanelLabel()
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Self.currency(projected.projectedBalance))
                            .font(.pccReadout(24))
                            .foregroundStyle(projected.projectedBalance < 0 ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme))
                    }
                    .padding(.top, 4)
                } else {
                    Text("No Account selected").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
        } header: {
            panelHeader("Projected Balance", systemImage: "chart.bar.doc.horizontal", status: projectedBalanceStatus)
        }
        .panelRows()
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
