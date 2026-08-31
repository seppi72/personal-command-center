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
/// Every panel header carries a `StatusDot` (`GlassDesignSystem.swift`)
/// computed from the same data the panel shows — the deliberate "read the
/// lamp, not every gauge" hierarchy device this screen is built around, so
/// a glance at the top of the screen (or the status strip above the panels
/// entirely) says what needs attention before you've read a single number.
///
/// Mostly a glance, with one deliberate exception: the Productivity panel's
/// mini Timer lets the owner pick a Task/Project/Client/Course and
/// start/stop right from here, reading and mutating the same shared
/// `TimerViewModel` instance the full Timer screen uses — every other panel
/// stays read-only, handing off to its full screen via a tappable header.
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

    /// The mini Timer's own pending selection, separate from the full
    /// `TimerView`'s own identical `@State` — each screen owns its own
    /// in-progress pick before `timerViewModel.start(container:)` commits
    /// it, the same way two independent forms would.
    @State private var timerSelectedKind: ContainerKind = .task
    @State private var timerSelectedItemID: UUID?

    @Environment(\.colorScheme) private var colorScheme

    /// Below this available width, Work and Productivity stack in one
    /// column instead of sitting side by side — narrower than that and two
    /// half-width panels would squeeze their charts and controls too tight
    /// to read.
    private static let wideLayoutThreshold: CGFloat = 620

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
                    .padding(16)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                .glassScreenBackground()
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

    /// The primary "readout" accent — see `Font.pccReadout`'s doc comment
    /// for why a hero number gets this color rather than one of the
    /// urgency-signaling colors `PanelStatus` uses.
    private var readoutColor: Color {
        GlassStyle.signalCyan(for: colorScheme)
    }

    // MARK: - Status strip

    /// A one-line summary above every panel — the first thing read on this
    /// screen, before any individual panel's own detail. Answers "does
    /// anything need me right now?" without requiring a glance at three
    /// separate panels to find out.
    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(overallStatus)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
            Text(Self.dateStripText())
                .pccPanelLabel()
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(GlassStyle.panelLine(for: colorScheme))
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

    private static func dateStripText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: Date()).uppercased()
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
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                panelHeader("Finances", systemImage: "dollarsign.circle", status: viewModel.financesStatus, action: onTapFinances)
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Net Worth")
                            .pccPanelLabel()
                            .foregroundStyle(.secondary)
                        Text(Self.currency(viewModel.currentNetWorth))
                            .font(.pccReadout(40))
                            .foregroundStyle(readoutColor)
                    }
                    Spacer()
                    financesRangeControl
                }
                incomeExpenseChart
            }
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
            Text("Nothing logged for this range yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            netTrendChart
            incomeExpenseGauges
        }
    }

    private var netTrendChart: some View {
        Chart(viewModel.financeBuckets) { bucket in
            AreaMark(
                x: .value("Period", bucket.periodStart, unit: viewModel.financeBucketUnit),
                y: .value("Net", bucket.net)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [readoutColor.opacity(0.30), readoutColor.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Period", bucket.periodStart, unit: viewModel.financeBucketUnit),
                y: .value("Net", bucket.net)
            )
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
        .frame(height: 120)
    }

    private var incomeExpenseGauges: some View {
        let maxValue = max(totalIncome, totalExpense, 1)
        return VStack(spacing: 8) {
            gaugeRow(label: "Income", value: totalIncome, maxValue: maxValue, color: GlassStyle.signalGreen(for: colorScheme))
            gaugeRow(label: "Expense", value: totalExpense, maxValue: maxValue, color: GlassStyle.signalRed(for: colorScheme))
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
                        .fill(GlassStyle.panelLine(for: colorScheme))
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
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                panelHeader("Work", systemImage: "briefcase", status: viewModel.workStatus, action: onTapProjects)
                projectsProgressContent
                Divider()
                taskList(
                    title: "Today", tasks: viewModel.tasksDueToday, emptyText: "Nothing due today",
                    indicatorColor: GlassStyle.signalAmber(for: colorScheme))
                taskList(
                    title: "Overdue", tasks: viewModel.tasksOverdue, emptyText: "Nothing overdue",
                    indicatorColor: GlassStyle.signalRed(for: colorScheme))
                Divider()
                completionRateContent
            }
        }
    }

    /// A horizontal bar per Project with at least one Task, its length the
    /// fraction of that Project's Tasks that are complete. Capped to the 5
    /// furthest-from-done Projects so a busy Projects list doesn't turn this
    /// panel into its own scroll view — sorted ascending by completion so
    /// the Projects most needing attention are the ones shown.
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
                .foregroundStyle(readoutColor)
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
        if rate >= 0.8 { return GlassStyle.signalGreen(for: colorScheme) }
        if rate >= 0.5 { return GlassStyle.signalAmber(for: colorScheme) }
        return GlassStyle.signalRed(for: colorScheme)
    }

    // MARK: - Productivity card

    private var productivityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                panelHeader("Productivity", systemImage: "bolt.fill", status: productivityStatus)
                miniTimerContent
                Divider()
                workHoursContent
            }
        }
    }

    /// `.active` (the readout-cyan lamp) while a Timer is running, `.idle`
    /// otherwise — this panel's lamp signals live state rather than
    /// urgency, the other meaning `PanelStatus` carries (see its own doc
    /// comment).
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
                        .foregroundStyle(readoutColor)
                }
                Button("Stop") {
                    Task { await timerViewModel.stop() }
                }
                .buttonStyle(.borderedProminent)
                .tint(GlassStyle.signalRed(for: colorScheme))
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
                Button("Start") {
                    guard let timerSelectedItemID else { return }
                    Task { await timerViewModel.start(container: miniContainer(itemID: timerSelectedItemID)) }
                }
                .buttonStyle(.borderedProminent)
                .tint(readoutColor)
                .disabled(timerSelectedItemID == nil)
            }
        }
    }

    /// The mini Timer's compact Task/Project/Client/Course tab row — reuses
    /// `TimerView`'s own `ContainerKind` enum rather than a second copy.
    /// Switching tabs clears `timerSelectedItemID`: an id from the old
    /// kind's list wouldn't mean anything against the new kind's items.
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
                        .foregroundStyle(kind == timerSelectedKind ? readoutColor : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(kind == timerSelectedKind ? readoutColor.opacity(0.15) : Color.clear)
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

    /// Mirrors `TimerView.containerLabel(for:)`.
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

    /// Mirrors `TimerView.formattedElapsed(_:)`.
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
                    .foregroundStyle(readoutColor)
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

    private static func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: "PHP"))
    }
}
