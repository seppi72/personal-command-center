import Charts
import SwiftUI

/// The app's landing screen: a status strip, then three instrument panels —
/// Finances (a Net Worth readout + a net trend trace + income/expense
/// gauges over a selectable date range), Work (Projects Progress, today's-
/// and-overdue Tasks, and an on-time completion rate), and Productivity (a
/// mini, fully-interactive Timer plus this week's Work Hours). One shared
/// SwiftUI view for both platforms, no platform-specific chrome, per this
/// package's existing "minimal" scope (mirrors `DeadlinesView`/
/// `TransactionsView`).
///
/// Every panel header carries a `StatusDot` (`PCCChassis.swift`)
/// computed from the same data the panel shows — the deliberate "read the
/// lamp, not every gauge" hierarchy device this screen is built around, so
/// a glance at the top of the screen (or the status strip above the panels
/// entirely) says what needs attention before you've read a single number.
///
/// On the shared Liquid Glass system since issue #73, landed last among the
/// sixteen screens (issue #65) so this hub's own summaries could be tuned
/// against every other screen's finished glass look rather than the other
/// way around. The earlier "Command Deck" identity — `HUDCorners`'
/// viewfinder brackets, a live ticking clock, and every hero readout in the
/// chassis's own cyan accent — is gone along with it: this screen
/// deliberately carries **no accent of its own**, since it exists to
/// summarize the screens beneath it rather than to have a vibe those
/// screens compete with. Its `StatusDot`s, plus the app-wide green/red/amber
/// meaning rules (money in vs. out, overdue vs. on schedule, a completion
/// rate's tier) are the only color anywhere on it; a figure with no such
/// rule to apply — Projects Progress, the mini Timer's elapsed digits, this
/// week's Work Hours — renders in plain `.primary`/`.secondary`, same as "a
/// task count and a client name get no accent" reads everywhere else in the
/// glass system.
///
/// Mostly a glance, with one deliberate exception: the Productivity panel's
/// mini Timer lets the owner pick a Task/Project/Client/Course and
/// start/stop right from here, reading and mutating the same shared
/// `TimerViewModel` instance the Time Entries screen's own hero timer
/// uses — every other panel stays read-only, handing off to its full
/// screen via a tappable header.
///
/// `Screen` (the sidebar's navigation enum) lives in the `PCCDesktop`
/// executable target, not in this package, so this view can't reference it
/// directly — `PCCUI` has no dependency in that direction. Explicit
/// closures keep this view decoupled from any particular host app's
/// navigation model, the same way every other `PCCUI` screen has no
/// awareness of the sidebar that hosts it.
public struct OverviewView: View {
    @ObservedObject private var viewModel: OverviewViewModel
    @ObservedObject private var timerViewModel: TimerViewModel
    private let onTapFinances: () -> Void
    private let onTapProjects: () -> Void
    private let onTapTasks: () -> Void

    public init(
        viewModel: OverviewViewModel,
        timerViewModel: TimerViewModel,
        onTapFinances: @escaping () -> Void,
        onTapProjects: @escaping () -> Void,
        onTapTasks: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.timerViewModel = timerViewModel
        self.onTapFinances = onTapFinances
        self.onTapProjects = onTapProjects
        self.onTapTasks = onTapTasks
    }

    public var body: some View {
        OverviewContent(
            viewModel: viewModel,
            timerViewModel: timerViewModel,
            onTapFinances: onTapFinances,
            onTapProjects: onTapProjects,
            onTapTasks: onTapTasks
        )
        .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `OverviewView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required, not optional —
/// `FinancesReportingView`/`FinancesReportingContent` hit this the hard
/// way first.
private struct OverviewContent: View {
    @ObservedObject var viewModel: OverviewViewModel
    @ObservedObject var timerViewModel: TimerViewModel
    let onTapFinances: () -> Void
    let onTapProjects: () -> Void
    let onTapTasks: () -> Void

    /// The mini Timer's own pending selection, separate from
    /// `WorkView`'s own identical `@State` for its toolbar timer chip — each
    /// screen owns its own in-progress pick before
    /// `timerViewModel.start(container:)` commits it, the same way two
    /// independent forms would.
    @State private var timerSelectedKind: ContainerKind = .task
    @State private var timerSelectedItemID: UUID?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    /// Below this available width, Work and Productivity stack in one
    /// column instead of sitting side by side — narrower than that and two
    /// half-width panels would squeeze their charts and controls too tight
    /// to read.
    private static let wideLayoutThreshold: CGFloat = 620

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        statusStrip
                        financesCard
                        if proxy.size.width > Self.wideLayoutThreshold {
                            HStack(alignment: .top, spacing: 16) {
                                workCard
                                productivityCard
                            }
                        } else {
                            workCard
                            productivityCard
                        }
                    }
                    .padding(PCCChassis.outerMargin)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                .background(GlassScreenBackground())
            }
            .navigationTitle("Overview")
            .task { await viewModel.load() }
            .task { await timerViewModel.load() }
            .refreshable {
                async let overviewLoad: Void = viewModel.load()
                async let timerLoad: Void = timerViewModel.load()
                _ = await (overviewLoad, timerLoad)
            }
            .errorAlert($viewModel.errorMessage)
            .errorAlert($timerViewModel.errorMessage)
        }
    }

    /// This screen's shared chart/figure container — the glass counterpart
    /// to the now-deleted console chassis's `PanelCard` widget, matching
    /// `FinancesReportingContent.glassPanel(content:)`. A fixed `minHeight`
    /// (rather than `FinancesReportingContent`'s content-sized panels) keeps
    /// Work and Productivity the same height when the wide layout sits them
    /// side by side — the same 220pt floor `PanelCard` gave every widget on
    /// the old console chassis, kept here as a literal now that the widget
    /// itself is gone.
    private func glassPanel<Content: View>(minHeight: CGFloat = 220, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .glassBubble(.fullWidth)
    }

    // MARK: - Directional signal
    //
    // Mirrors `FinancesReportingContent`'s identically-named helpers: the
    // one comparison every trend chart's color on this screen is derived
    // from, and the sign-based coloring a real money figure (Net Worth)
    // takes under the app-wide "green means money in or a positive
    // position, red means money out or negative" rule.

    private enum TrendDirection {
        case up, down, flat
    }

    private static func trendDirection(from buckets: [FinanceBucket]) -> TrendDirection {
        guard buckets.count > 1, let first = buckets.first, let last = buckets.last else { return .flat }
        if last.net > first.net { return .up }
        if last.net < first.net { return .down }
        return .flat
    }

    /// Chart traces are never neutral — unlike a strict up/down/flat
    /// reading, `.flat` still reads as green here, since a flat net trace
    /// isn't a loss.
    private func chartColor(for direction: TrendDirection) -> Color {
        direction == .down ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme)
    }

    private func signedColor(_ value: Double) -> Color {
        value < 0 ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme)
    }

    // MARK: - Status strip

    /// A one-line summary above every panel — the first thing read on this
    /// screen, before any individual panel's own detail. Answers "does
    /// anything need me right now?" without requiring a glance at three
    /// separate panels to find out. The right-hand side still ticks a real
    /// clock (`clockText(at:)`), kept through the glass migration — unlike
    /// `HUDCorners`, a live clock carries actual information rather than
    /// being costume, so it's untouched by issue #73's "no accent" and
    /// "HUD corners deleted" acceptance criteria.
    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(overallStatus)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.clockText(at: context.date))
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var overallStatus: PanelStatus {
        viewModel.tasksOverdue.isEmpty ? .nominal : .critical
    }

    private var statusStripText: String {
        let overdueCount = viewModel.tasksOverdue.count
        let overdueText = overdueCount > 0 ? "\(overdueCount) OVERDUE" : "ALL CLEAR"
        let timerText = timerViewModel.activeTimer != nil ? "TIMER RUNNING" : "TIMER IDLE"
        return "\(overdueText)   ·   \(timerText)"
    }

    private static func clockText(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d — HH:mm:ss"
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Panel header

    private func panelHeader(
        _ title: String, systemImage: String, status: PanelStatus, action: (() -> Void)? = nil
    ) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    panelHeaderLabel(title, systemImage: systemImage, status: status, showsChevron: true)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            } else {
                panelHeaderLabel(title, systemImage: systemImage, status: status, showsChevron: false)
            }
        }
    }

    private func panelHeaderLabel(
        _ title: String, systemImage: String, status: PanelStatus, showsChevron: Bool
    ) -> some View {
        HStack(spacing: 8) {
            StatusDot(status)
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Finances card

    private var financesCard: some View {
        glassPanel {
            panelHeader("Finances", systemImage: "dollarsign.circle", status: viewModel.financesStatus, action: onTapFinances)
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net Worth")
                        .pccPanelLabel()
                        .foregroundStyle(.secondary)
                    Text(Self.currency(viewModel.currentNetWorth))
                        .font(.pccReadout(40))
                        .foregroundStyle(signedColor(viewModel.currentNetWorth))
                }
                Spacer()
                financesRangeControl
            }
            incomeExpenseChart
        }
    }

    private var financesRangeControl: some View {
        PCCDateRangeControl(selection: $viewModel.financesDateRange) {
            Task { await viewModel.loadFinancesCard() }
        }
    }

    /// A net trend trace (one `AreaMark` + `LineMark` pair, hairline
    /// gridlines, monospaced axis labels — an oscilloscope reading, not a
    /// default chart-library combo chart) plus two small level gauges
    /// underneath giving the period's raw Income/Expense totals. Split
    /// this way rather than the old grouped-bar-plus-line-in-one-chart
    /// shape: the trace answers "which way is this going," the gauges
    /// answer "how much of each," and neither has to compromise its own
    /// scale to share an axis with the other.
    @ViewBuilder
    private var incomeExpenseChart: some View {
        if viewModel.financeBuckets.isEmpty {
            emptyChartLabel
        } else {
            netTrendChart
            incomeExpenseGauges
        }
    }

    /// Colored by whether the range's net figure rose or fell, matching
    /// `FinancesReportingContent.trendChart(_:valueLabel:)` — the same
    /// directional green/red rule, not the chassis's own accent, since a
    /// net trend genuinely has a "good direction" to signal.
    private var netTrendChart: some View {
        let color = chartColor(for: Self.trendDirection(from: viewModel.financeBuckets))
        return Chart(viewModel.financeBuckets) { bucket in
            AreaMark(
                x: .value("Period", bucket.periodStart, unit: viewModel.financeBucketUnit),
                y: .value("Net", bucket.net)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.30), color.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Period", bucket.periodStart, unit: viewModel.financeBucketUnit),
                y: .value("Net", bucket.net)
            )
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
        .frame(height: 120)
    }

    private var incomeExpenseGauges: some View {
        let maxValue = max(totalIncome, totalExpense, 1)
        return VStack(spacing: 8) {
            gaugeRow(label: "Income", value: totalIncome, maxValue: maxValue, color: theme.signalGreen(colorScheme))
            gaugeRow(label: "Expense", value: totalExpense, maxValue: maxValue, color: theme.signalRed(colorScheme))
        }
    }

    private func gaugeRow(label: String, value: Double, maxValue: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.panelLine(colorScheme))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(maxValue > 0 ? value / maxValue : 0))
                }
            }
            .frame(height: 6)
            Text(Self.currency(value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var totalIncome: Double {
        viewModel.financeBuckets.reduce(0) { $0 + $1.income }
    }

    private var totalExpense: Double {
        viewModel.financeBuckets.reduce(0) { $0 + $1.expense }
    }

    // MARK: - Work card

    private var workCard: some View {
        glassPanel {
            panelHeader("Work", systemImage: "briefcase", status: viewModel.workStatus, action: onTapProjects)
            projectsProgressContent
            Divider()
            taskList(
                title: "Today", tasks: viewModel.tasksDueToday, emptyText: "Nothing due today",
                indicatorColor: theme.signalAmber(colorScheme))
            taskList(
                title: "Overdue", tasks: viewModel.tasksOverdue, emptyText: "Nothing overdue",
                indicatorColor: theme.signalRed(colorScheme))
            Divider()
            completionRateContent
        }
    }

    /// A horizontal bar per Project with at least one Task, its length the
    /// fraction of that Project's Tasks that are complete. Capped to the 5
    /// furthest-from-done Projects so a busy Projects list doesn't turn this
    /// panel into its own scroll view — sorted ascending by completion so
    /// the Projects most needing attention are the ones shown. Bars render
    /// in plain `.secondary` rather than a signal color: completion has no
    /// green/red/amber meaning of its own on this screen (that's what the
    /// Work panel's `StatusDot` and the Today/Overdue lists already carry).
    @ViewBuilder
    private var projectsProgressContent: some View {
        let rows = viewModel.projectCompletion.sorted { $0.fraction < $1.fraction }.prefix(5)
        if rows.isEmpty {
            Text("No Projects with Tasks yet")
                .foregroundStyle(.secondary)
        } else {
            Chart(Array(rows), id: \.project.id) { row in
                BarMark(
                    x: .value("Complete", row.fraction),
                    y: .value("Project", row.project.name)
                )
                .foregroundStyle(.secondary)
                .cornerRadius(2)
                .annotation(position: .trailing) {
                    Text(row.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: CGFloat(rows.count) * 28 + 8)
        }
    }

    private func taskList(title: String, tasks: [PCCTask], emptyText: String, indicatorColor: Color) -> some View {
        let sorted = tasks.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let capped = Array(sorted.prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            if capped.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(capped) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(indicatorColor)
                            .frame(width: 5, height: 5)
                        Text(task.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        if let dueDate = task.dueDate {
                            Text(dueDate, style: .date)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                let remaining = sorted.count - capped.count
                if remaining > 0 {
                    moreRow(count: remaining, action: onTapTasks)
                }
            }
        }
    }

    @ViewBuilder
    private var completionRateContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On-Time Completion")
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            if let rate = viewModel.taskCompletionRateWithinDeadline {
                Text(rate, format: .percent.precision(.fractionLength(0)))
                    .font(.pccReadout(22))
                    .foregroundStyle(completionRateColor(rate))
            } else {
                Text("Not enough data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Colors the completion-rate readout itself by the same three-tier
    /// thresholds a `PanelStatus` would use, rather than leaving it neutral
    /// — this number is the one figure on the Work panel worth a second
    /// glance beyond the header lamp, so it earns its own signal color.
    private func completionRateColor(_ rate: Double) -> Color {
        if rate >= 0.8 { return theme.signalGreen(colorScheme) }
        if rate >= 0.5 { return theme.signalAmber(colorScheme) }
        return theme.signalRed(colorScheme)
    }

    // MARK: - Productivity card

    private var productivityCard: some View {
        glassPanel {
            panelHeader("Productivity", systemImage: "bolt.fill", status: productivityStatus)
            miniTimerContent
            Divider()
            workHoursContent
        }
    }

    /// `.active` while a Timer is running, `.idle` otherwise — this panel's
    /// lamp signals live state rather than urgency, the other meaning
    /// `PanelStatus` carries (see its own doc comment). `.active` resolves
    /// to `theme.accent`, which on `ScreenTheme.liquidGlass` is the same
    /// green as `signalGreen` — this screen's "no accent" rule holds
    /// without this shared, chassis-wide mapping needing a special case.
    private var productivityStatus: PanelStatus {
        timerViewModel.activeTimer != nil ? .active : .idle
    }

    @ViewBuilder
    private var miniTimerContent: some View {
        if let activeTimer = timerViewModel.activeTimer {
            VStack(alignment: .leading, spacing: 8) {
                Text(timerContainerLabel(for: activeTimer))
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: activeTimer.startDate, by: 1)) { context in
                    Text(Self.formattedElapsed(context.date.timeIntervalSince(activeTimer.startDate)))
                        .font(.pccReadout(30))
                        .foregroundStyle(.primary)
                }
                // `signalRed`, not an accent — predates the glass migration
                // and is untouched by it: stopping a running Timer maps
                // cleanly enough onto "ending something" that this stayed
                // as-is rather than being flattened to neutral along with
                // everything else this screen no longer accents.
                Button("Stop") {
                    Task { await timerViewModel.stop() }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.signalRed(colorScheme))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                miniKindTabs
                PCCMenuPicker(
                    "Attach to",
                    selection: $timerSelectedItemID,
                    options: miniCurrentItems.map { (Optional($0.id), $0.title) },
                    style: .boxed,
                    placeholder: "Choose a \(timerSelectedKind.title)"
                )
                // `.primary`, not `signalGreen`: unlike Stop above,
                // starting a Timer has no ready-made green/red/amber
                // meaning under this screen's rules, and `readoutColor`
                // (what this button tinted pre-migration) no longer
                // exists now that Overview carries no accent of its own.
                Button("Start") {
                    guard let timerSelectedItemID else { return }
                    Task { await timerViewModel.start(container: miniContainer(itemID: timerSelectedItemID)) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .disabled(timerSelectedItemID == nil)
            }
        }
    }

    /// The mini Timer's compact Task/Project/Client/Course tab row — reuses
    /// the shared `ContainerKind` enum (`TimerViewModel.swift`) rather than
    /// a second copy.
    /// Switching tabs clears `timerSelectedItemID`: an id from the old
    /// kind's list wouldn't mean anything against the new kind's items.
    /// The selected tab is marked by weight and a neutral capsule fill
    /// rather than an accent color — which kind is picked carries no
    /// green/red/amber meaning of its own.
    private var miniKindTabs: some View {
        HStack(spacing: 4) {
            ForEach(ContainerKind.allCases) { kind in
                Button {
                    guard kind != timerSelectedKind else { return }
                    timerSelectedKind = kind
                    timerSelectedItemID = nil
                } label: {
                    Text(kind.title)
                        .font(.caption.weight(kind == timerSelectedKind ? .bold : .regular))
                        .foregroundStyle(kind == timerSelectedKind ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(kind == timerSelectedKind ? theme.panelLine(colorScheme) : Color.clear)
                        )
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
        }
    }

    private var miniCurrentItems: [(id: UUID, title: String)] {
        switch timerSelectedKind {
        case .task: return timerViewModel.tasks.map { ($0.id, $0.title) }
        case .project: return timerViewModel.projects.map { ($0.id, $0.name) }
        case .client: return timerViewModel.clients.map { ($0.id, $0.name) }
        case .course: return timerViewModel.courses.map { ($0.id, $0.name) }
        }
    }

    private func miniContainer(itemID: UUID) -> TimeEntryContainer {
        switch timerSelectedKind {
        case .task: return .task(itemID)
        case .project: return .project(itemID)
        case .client: return .client(itemID)
        case .course: return .course(itemID)
        }
    }

    /// Mirrors `WorkViewModel.containerLabel(for:)`, against
    /// `timerViewModel`'s own copies of the same picker lists rather than
    /// `WorkViewModel`'s, since this panel only ever observes
    /// `timerViewModel`.
    private func timerContainerLabel(for entry: TimeEntry) -> String {
        if let taskID = entry.taskID {
            return timerViewModel.tasks.first { $0.id == taskID }?.title ?? "Unknown Task"
        }
        if let projectID = entry.projectID {
            return timerViewModel.projects.first { $0.id == projectID }?.name ?? "Unknown Project"
        }
        if let clientID = entry.clientID {
            return timerViewModel.clients.first { $0.id == clientID }?.name ?? "Unknown Client"
        }
        if let courseID = entry.courseID {
            return timerViewModel.courses.first { $0.id == courseID }?.name ?? "Unknown Course"
        }
        return "Unattached"
    }

    /// Mirrors `WorkView`'s own `formattedElapsed(_:)`.
    private static func formattedElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    @ViewBuilder
    private var workHoursContent: some View {
        let totalHours = viewModel.workHoursThisWeek.reduce(0) { $0 + $1.totalSeconds } / 3600
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", totalHours))
                    .font(.pccReadout(18))
                Text("Hrs This Week")
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
            }
            if viewModel.workHoursThisWeek.isEmpty {
                Text("No Work Hours logged this week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(viewModel.workHoursThisWeek, id: \.date) { row in
                    BarMark(
                        x: .value("Day", row.date ?? Date(), unit: .day),
                        y: .value("Hours", row.totalSeconds / 3600)
                    )
                    .foregroundStyle(.secondary)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 90)
            }
        }
    }

    // MARK: - Shared

    private func moreRow(count: Int, action: @escaping () -> Void) -> some View {
        Button("+\(count) more", action: action)
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
            .foregroundStyle(.secondary)
    }

    private var emptyChartLabel: some View {
        Text("Nothing logged for this range yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private static func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: "PHP"))
    }
}
