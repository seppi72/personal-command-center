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
/// Ticket #66 moved this screen onto the shared Liquid Glass chassis
/// (`ScreenTheme.liquidGlass`, `GlassScreenBackground`, `GlassBubble`),
/// replacing what was a screen-specific "Trading Desk" vibe — a gold accent
/// and a warmer near-black void, both gone now — with the same plain
/// white/black ground and translucent glass panels `AccountsView` and
/// `CategoriesView` already carry. Every chart panel below is a
/// `glassPanel(_:)`, the glass counterpart to the console chassis's
/// `.panelRows()` card. Directional `signalGreen`/`signalRed` coloring is
/// untouched — that convention was already right, and it's now the
/// screen's *only* accent: a rising figure is green, a falling or negative
/// one is red, and nothing on this screen reaches for a "primary" color
/// otherwise, per the app-wide meaning rules every other converted screen
/// follows.
///
/// Every panel header is a nameplate — a `StatusDot` plus an uppercase
/// tracked-out label, matching `OverviewView`'s panel headers — and every
/// chart keeps that same system's hairline-trace language (dashed
/// gridlines, monospaced axis labels, a gradient-filled `AreaMark` under a
/// thin `LineMark`) instead of `Charts`' default chrome.
///
/// This screen's one signature device, kept through the glass migration: a
/// ticker-style headline strip (hero Net Worth readout + a `DeltaBadge`
/// showing signed change and percent over the selected range, the same
/// "number + colored delta" convention every stock/banking ticker uses)
/// and `TickerTape` — every Account's balance streaming past in a
/// continuous scroll, stock-exchange-board style, now reskinned onto the
/// same Material-backed glass every bubble on this screen uses instead of
/// an opaque panel fill. It's the one thing that makes this read as a live
/// feed rather than a report generated once, and the one screen that still
/// owns that device, because the figures it shows genuinely move.
public struct FinancesReportingView: View {
    @ObservedObject private var viewModel: FinancesReportingViewModel

    public init(viewModel: FinancesReportingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        FinancesReportingContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content, split out from `FinancesReportingView`
/// itself so `.screenTheme(.liquidGlass)` — applied in that struct's body,
/// above — is genuinely in effect by the time this struct's own `body`
/// reads `@Environment(\.screenTheme)`. A view's environment modifiers
/// only affect the subtree they wrap; they don't reach back into that
/// same view's own body computation. `FinancesReportingView` calling
/// `.screenTheme()` on *itself* would never change what `theme` resolved
/// to had it tried to read the environment directly in its own body — the
/// override only becomes visible to a genuinely separate child view,
/// which is what this struct is. (Caught the hard way: the first build
/// rendered the default cyan accent instead of this screen's own color,
/// because the hero Net Worth color was computed directly in the struct
/// that also applied the theme override, rather than in a child of it.)
private struct FinancesReportingContent: View {
    @ObservedObject var viewModel: FinancesReportingViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    /// A `ScrollView` of glass panels rather than a `List` — this screen's
    /// charts and `TickerTape` need to draw their own translucent
    /// Material-backed shapes (the shared `GlassBubble`), which a `List`'s
    /// opaque native row chrome can't host (mirrors `AccountsView`'s and
    /// `CategoriesView`'s own move from `List` to `ScrollView` + custom
    /// cards for the same reason). One outer padding on the whole `VStack`
    /// — `PCCChassis.outerMargin` — replaces what used to be the `List`'s
    /// own frame padding, for the same reason that padding was on the
    /// `List`'s frame rather than a per-row inset: it moves every panel in
    /// together, not just each row's foreground content.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !viewModel.accounts.isEmpty {
                        TickerTape(accounts: viewModel.accounts)
                    }
                    tickerStrip
                    netWorthSection
                    accountBalanceSection
                    expensesSection
                    projectedBalanceSection
                }
                .padding(PCCChassis.outerMargin)
            }
            .background(GlassScreenBackground())
            .navigationTitle("Finances Reporting")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    /// Net Worth's hero readout color, and the ledger rules under Projected
    /// Balance: both are directional figures, so both take the same
    /// green/red-by-sign coloring every balance on this screen uses
    /// (`AccountsView.AccountBubble.balanceColor` is the same convention) —
    /// there's no separate "primary" accent color on this screen to reach
    /// for instead.
    private func signedColor(_ value: Double) -> Color {
        value < 0 ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme)
    }

    /// This screen's shared chart/figure container — the glass counterpart
    /// to the console chassis's `.panelRows()` card, used by every section
    /// below. A panel's own `panelHeader(_:systemImage:status:)` is meant
    /// to be the first thing passed in.
    private func glassPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassBubble(.fullWidth)
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
                .foregroundStyle(signedColor(viewModel.currentNetWorth))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            deltaBadge(for: viewModel.netWorthTrend)
        }
    }

    /// `ViewThatFits` rather than a single fixed `HStack`: the date-range
    /// control's label plus a multi-figure PHP readout can together exceed
    /// a phone-portrait row's width, so the strip drops to two lines
    /// instead of clipping. Full-bleed, no panel chrome, bottom hairline —
    /// the same treatment `AccountsView`'s and `CategoriesView`'s own
    /// `statusStrip` uses, since this is this screen's status strip.
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
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Net Worth

    private var netWorthSection: some View {
        glassPanel {
            panelHeader("Net Worth", systemImage: "chart.line.uptrend.xyaxis", status: netWorthStatus)
            if viewModel.netWorthTrend.isEmpty {
                emptyChartLabel
            } else {
                trendChart(viewModel.netWorthTrend, valueLabel: "Net Worth")
            }
        }
    }

    private var netWorthStatus: PanelStatus {
        viewModel.currentNetWorth < 0 ? .critical : .nominal
    }

    // MARK: - Account Balance

    private var accountBalanceSection: some View {
        glassPanel {
            panelHeader("Account Balance", systemImage: "building.columns", status: accountBalanceStatus)
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
        glassPanel {
            panelHeader("Expenses per Day", systemImage: "arrow.down.circle", status: .idle)
            if viewModel.expensesPerDay.isEmpty {
                emptyChartLabel
            } else {
                expensesChart
            }
        }
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
        glassPanel {
            panelHeader("Projected Balance", systemImage: "chart.bar.doc.horizontal", status: projectedBalanceStatus)
            PCCMenuPicker(
                "Period",
                selection: $viewModel.projectedBalancePeriod,
                options: ProjectedBalancePeriod.allCases.map { ($0, $0.displayName) }
            )
            .onChange(of: viewModel.projectedBalancePeriod) { _ in
                Task { await viewModel.loadSelectedAccountFigures() }
            }
            if let projected = viewModel.projectedBalance {
                LabeledContent("Average Daily Net") {
                    Text(Self.currency(projected.averageDailyNet))
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                }
                // A double rule, the way a paper ledger closes out its
                // final sum with two rules instead of one — this is the
                // screen's actual bottom line, so it earns the same "this
                // is final" weight a real ledger gives a closing total,
                // not just a plain hairline divider. `panelLine`, not an
                // accent — this screen has none; the figure below the rule
                // already carries the color that matters.
                VStack(spacing: 2) {
                    Rectangle().fill(theme.panelLine(colorScheme)).frame(height: 1)
                    Rectangle().fill(theme.panelLine(colorScheme)).frame(height: 1)
                }
                .padding(.top, 4)
                HStack(alignment: .lastTextBaseline) {
                    Text("Projected Balance")
                        .pccPanelLabel()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.currency(projected.projectedBalance))
                        .font(.pccReadout(24))
                        .foregroundStyle(signedColor(projected.projectedBalance))
                }
                .padding(.top, 4)
            } else {
                Text("No Account selected").foregroundStyle(.secondary)
            }
        }
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

// MARK: - Ticker tape

/// This screen's signature device: every Account's balance streaming past
/// in a continuous, looping horizontal scroll — the stock-exchange-board
/// convention for "this is live," not a report generated once. Renders two
/// back-to-back copies of a "block" — the full Account list repeated just
/// enough times to be at least as wide as the visible bar — and animates
/// offset from 0 to exactly one block's width, on an unbounded linear
/// repeat — since the second copy is identical, the loop point is
/// invisible, and because the block is never narrower than the bar itself,
/// there's always real content to show, so the tape reads as one Account
/// circling back into the next rather than trailing off into blank space.
private struct TickerTape: View {
    let accounts: [Account]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Width of exactly one pass over every Account — the unit this
    /// marquee repeats, and the unit its scroll offset is measured in.
    @State private var singleRowWidth: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        // The looping content needs `.fixedSize()` so it lays out at its
        // own natural width instead of being squeezed into whatever width
        // its parent proposes — otherwise the copies wouldn't be
        // identical-width and the loop point would jump. But `.fixedSize()`
        // doesn't just affect this view's own layout: it also changes what
        // size THIS view reports upward to its parent, to its natural
        // (potentially very wide, unbounded) size rather than the parent's
        // proposal — and with Accounts rendered repeatedly with no cap
        // above it, that unbounded width was propagating all the way up
        // through this screen's `NavigationStack` to the enclosing
        // `NavigationSplitView` in `PCCDesktop`, which reacted to the
        // detail pane's huge reported ideal width by collapsing the
        // sidebar column to make room — permanently, since the pressure
        // was static content, not a one-off layout pass, so the sidebar
        // never got a reason to come back (issue: opening Finances closed
        // the sidebar for good). A `GeometryReader` doesn't have this
        // problem: it always reports back up exactly the size ITS OWN
        // parent proposed, regardless of what its content wants — so
        // wrapping the unbounded content in one here, and explicitly
        // clamping it to the `GeometryReader`'s own measured width rather
        // than letting it size itself, absorbs the runaway width before it
        // can reach `NavigationSplitView` at all.
        GeometryReader { outer in
            // Two back-to-back copies of the Account row (the classic
            // marquee trick) only loop seamlessly when a single copy is
            // already at least as wide as the visible bar — true on a
            // phone-width ticker, but not on a wide desktop window with
            // only a handful of Accounts. There, a single row fell short
            // of the bar's width, so once the tape had scrolled past the
            // last Account there was nothing left to show until the loop
            // caught up — a stretch of blank space after "Auto Loan"
            // (issue, caught via screenshot) instead of circling back to
            // the first Account. Repeating the full Account list
            // `copiesNeeded` times first turns it into one "block"
            // guaranteed at least as wide as the bar, and it's that
            // block — not the raw per-Account row — that gets doubled and
            // scrolled by exactly its own width, so the loop point is
            // always covered by real content.
            let copiesNeeded = Self.copiesNeeded(rowWidth: singleRowWidth, containerWidth: outer.size.width)
            let blockWidth = singleRowWidth * CGFloat(copiesNeeded)

            HStack(spacing: 0) {
                ForEach(0..<(copiesNeeded * 2), id: \.self) { _ in row }
            }
            .fixedSize()
            .background(
                // Measures a single pass over every Account, independent of
                // `copiesNeeded` above (which is itself derived from this
                // measurement) — a hidden single row rather than a fraction
                // of the visible, possibly-repeated block.
                row.fixedSize().hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: TapeWidthKey.self, value: proxy.size.width)
                        }
                    )
            )
            .offset(x: isAnimating ? -blockWidth : 0)
            .frame(width: outer.size.width, height: outer.size.height, alignment: .leading)
            .clipped()
            .onChange(of: blockWidth) { newWidth in
                guard newWidth > 0, !reduceMotion else { return }
                isAnimating = false
                withAnimation(.linear(duration: max(8, Double(newWidth) / 40)).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tapeBackground)
        .onPreferenceChange(TapeWidthKey.self) { width in
            // Only the first real measurement is kept — this fires on
            // every layout pass, and re-measuring on later, near-identical
            // widths would restart the scroll from 0 each time instead of
            // leaving it running.
            guard width > 0, singleRowWidth == 0 else { return }
            singleRowWidth = width
        }
    }

    /// How many back-to-back copies of the full Account list are needed so
    /// the resulting block is at least as wide as `containerWidth` — the
    /// invariant the two-copies-doubled marquee trick depends on. `1` until
    /// `rowWidth` has its first real measurement.
    private static func copiesNeeded(rowWidth: CGFloat, containerWidth: CGFloat) -> Int {
        guard rowWidth > 0 else { return 1 }
        return max(1, Int((containerWidth / rowWidth).rounded(.up)))
    }

    /// The tape's own glass surface — the same `Material` fill, white tint,
    /// and hairline rim `GlassBubble` draws with, cut to this bar's own
    /// squat shape rather than either of `GlassBubbleStyle`'s row/grid-cell
    /// presets (mirrors `AccountsView.AccountBubble.iconBubble`'s identical
    /// reasoning for its own non-preset shape). No specular highlight —
    /// that device reads on a bubble's open fill, not on a thin bar this
    /// busy with scrolling text.
    private var tapeBackground: some View {
        let shape = RoundedRectangle(cornerRadius: PCCChassis.cardCornerRadius, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(GlassBubble.tint(for: colorScheme)))
            .overlay(shape.strokeBorder(GlassBubble.rimColor(theme, colorScheme), lineWidth: GlassBubble.rimWidth))
    }

    private var row: some View {
        HStack(spacing: 0) {
            ForEach(accounts) { account in
                tapeItem(for: account)
            }
        }
    }

    private func tapeItem(for account: Account) -> some View {
        let color = account.balance < 0 ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme)
        return HStack(spacing: 8) {
            Text(account.name.uppercased())
                .foregroundStyle(.secondary)
            Text(Self.currency(account.balance))
                .foregroundStyle(color)
                .fontWeight(.semibold)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .overlay(
            Rectangle().fill(theme.panelLine(colorScheme)).frame(width: 1),
            alignment: .trailing
        )
    }

    private static func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: "PHP").sign(strategy: .always()))
    }
}

private struct TapeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
