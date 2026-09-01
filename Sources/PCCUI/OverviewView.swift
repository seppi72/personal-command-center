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
/// "Command Deck": this screen's own signature on top of the shared
/// chassis, chosen for the one screen whose whole job is "am I in control
/// right now" — `HUDCorners` frames the content in viewfinder/targeting-
/// reticle brackets (you're watching a live instrument, not reading a
/// static report), and the status strip's date is a real ticking clock
/// rather than a static string, reinforcing that the panels below are
/// live telemetry. Reuses the chassis's existing cyan/green/amber/red
/// palette as-is (`ScreenTheme.default`) — the signature here is entirely
/// in framing and motion, not a new color story.
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

    /// The mini Timer's own pending selection, separate from
    /// `TimeEntriesView`'s own identical `@State` for its hero timer — each
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
                ZStack {
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
                    .panelScreenBackground()

                    // Framed to the viewport, not the scroll content — sits
                    // in its own ZStack layer rather than as a ScrollView
                    // overlay so it stays put as a fixed frame instead of
                    // scrolling away with the panels underneath.
                    // Accent-colored, not the neutral hairline `panelLine`
                    // divider color uses — a real HUD's reticle marks are
                    // drawn in the display's own accent, and at panelLine's
                    // contrast against the light-mode void these were
                    // effectively invisible (caught on the first real
                    // screenshot: no brackets visible at all).
                    HUDCorners(color: theme.accent(colorScheme).opacity(0.55))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                }
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
        theme.accent(colorScheme)
    }

    // MARK: - Status strip

    /// A one-line summary above every panel — the first thing read on this
    /// screen, before any individual panel's own detail. Answers "does
    /// anything need me right now?" without requiring a glance at three
    /// separate panels to find out. The right-hand side ticks a real clock
    /// (`clockText(at:)`) rather than showing a static date — a still
    /// timestamp reads as a report generated once; a moving one reads as
    /// telemetry you're watching live, which is the whole point of the
    /// "Command Deck" framing this screen carries.
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
        PanelCard {
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
        PanelCard {
            VStack(alignment: .leading, spacing: 16) {
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
        if rate >= 0.8 { return theme.signalGreen(colorScheme) }
        if rate >= 0.5 { return theme.signalAmber(colorScheme) }
        return theme.signalRed(colorScheme)
    }

    // MARK: - Productivity card

    private var productivityCard: some View {
        PanelCard {
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
    /// the shared `ContainerKind` enum (`TimerViewModel.swift`) rather than
    /// a second copy.
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

    /// Mirrors `TimeEntriesViewModel.containerLabel(for:)`, against
    /// `timerViewModel`'s own copies of the same picker lists rather than
    /// `TimeEntriesViewModel`'s, since this panel only ever observes
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

    /// Mirrors `TimeEntriesView.formattedElapsed(_:)`.
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

// MARK: - HUD corners

/// This screen's signature framing device: four independent viewfinder/
/// targeting-reticle corner marks around the content area, rather than a
/// single full-rectangle border stroke — a complete border reads as a
/// panel outline (decoration); four open corners read as a frame you're
/// looking *through*, the same device a camera viewfinder or a HUD uses to
/// say "this is what's being tracked" without boxing it in on every side.
/// Scoped to `OverviewView` alone, not promoted to the shared chassis —
/// this is Overview's own vibe, not a device every screen should reach
/// for.
private struct HUDCorners: View {
    var color: Color

    private let length: CGFloat = 22
    private let thickness: CGFloat = 2

    var body: some View {
        ZStack {
            mark(top: true, leading: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            mark(top: true, leading: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            mark(top: false, leading: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            mark(top: false, leading: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    /// One "L": a vertical stroke on whichever side (`leading`) plus a
    /// horizontal stroke on whichever edge (`top`), meeting at that
    /// corner. Built as a *single* continuous subpath (moveTo once, two
    /// addLines through the shared corner vertex) rather than two
    /// separate move/line pairs — the two-subpath version silently
    /// dropped its vertical arm specifically for the top-leading corner,
    /// where both subpaths' `move(to:)` happened to land on the exact
    /// same point (0, 0); one continuous path has no duplicate moveTo to
    /// trip over, for any corner.
    private func mark(top: Bool, leading: Bool) -> some View {
        let cornerX: CGFloat = leading ? 0 : length
        let cornerY: CGFloat = top ? 0 : length
        let verticalFarY: CGFloat = top ? length : 0
        let horizontalFarX: CGFloat = leading ? length : 0
        return Path { path in
            path.move(to: CGPoint(x: cornerX, y: verticalFarY))
            path.addLine(to: CGPoint(x: cornerX, y: cornerY))
            path.addLine(to: CGPoint(x: horizontalFarX, y: cornerY))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .square, lineJoin: .miter))
        .frame(width: length, height: length)
    }
}
