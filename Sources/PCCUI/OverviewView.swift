import Charts
import SwiftUI

/// The app's landing screen: three glass cards — Finances (Net Worth + an
/// income/expense/net chart over a selectable date range), Work (Projects
/// Progress, today's-and-overdue Tasks, and an on-time completion rate),
/// and Productivity (a mini, fully-interactive Timer plus this week's Work
/// Hours). One shared SwiftUI view for both platforms, no
/// platform-specific chrome, per this package's existing "minimal" scope
/// (mirrors `DeadlinesView`/`TransactionsView`).
///
/// Mostly a glance, with one deliberate exception: the Productivity card's
/// mini Timer lets the owner pick a Task/Project/Client/Course and
/// start/stop right from here, reading and mutating the same shared
/// `TimerViewModel` instance the full Timer screen uses — every other card
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
            ScrollView {
                VStack(spacing: 16) {
                    financesCard
                    workCard
                    productivityCard
                }
                .padding(16)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .glassScreenBackground()
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

    private func cardHeader(_ title: String, systemImage: String, action: (() -> Void)? = nil) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    cardHeaderLabel(title, systemImage: systemImage, showsChevron: true)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            } else {
                cardHeaderLabel(title, systemImage: systemImage, showsChevron: false)
            }
        }
    }

    private func cardHeaderLabel(_ title: String, systemImage: String, showsChevron: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Finances card

    private var financesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader("Finances", systemImage: "dollarsign.circle", action: onTapFinances)
                Text(Self.currency(viewModel.currentNetWorth))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                financesRangeControl
                incomeExpenseChart
            }
        }
    }

    private var financesRangeControl: some View {
        PCCDateRangeControl(selection: $viewModel.financesDateRange) {
            Task { await viewModel.loadFinancesCard() }
        }
    }

    /// Grouped Income/Expense bars per period plus a Net line overlay — two
    /// `BarMark`s and one `LineMark` per bucket, each tagged with a "Type"
    /// style value so Swift Charts colors and legends all three series from
    /// one `chartForegroundStyleScale`. Green/red for income/expense matches
    /// the sign coloring every other money figure in this package already
    /// uses (e.g. `TransactionsView`'s own row amounts).
    @ViewBuilder
    private var incomeExpenseChart: some View {
        if viewModel.financeBuckets.isEmpty {
            Text("Nothing logged for this range yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Chart(viewModel.financeBuckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.periodStart, unit: viewModel.financeBucketUnit),
                    y: .value("Amount", bucket.income)
                )
                .position(by: .value("Type", "Income"))
                .foregroundStyle(by: .value("Type", "Income"))

                BarMark(
                    x: .value("Period", bucket.periodStart, unit: viewModel.financeBucketUnit),
                    y: .value("Amount", bucket.expense)
                )
                .position(by: .value("Type", "Expense"))
                .foregroundStyle(by: .value("Type", "Expense"))

                LineMark(
                    x: .value("Period", bucket.periodStart, unit: viewModel.financeBucketUnit),
                    y: .value("Amount", bucket.net)
                )
                .foregroundStyle(by: .value("Type", "Net"))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale([
                "Income": Color.green,
                "Expense": Color.red,
                "Net": Color.accentColor,
            ])
            .frame(height: 180)
        }
    }

    // MARK: - Work card

    private var workCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader("Work", systemImage: "briefcase", action: onTapProjects)
                projectsProgressContent
                Divider()
                taskList(title: "Today", tasks: viewModel.tasksDueToday, emptyText: "Nothing due today")
                taskList(title: "Overdue", tasks: viewModel.tasksOverdue, emptyText: "Nothing overdue")
                Divider()
                completionRateContent
            }
        }
    }

    /// A horizontal bar per Project with at least one Task, its length the
    /// fraction of that Project's Tasks that are complete. Capped to the 5
    /// furthest-from-done Projects so a busy Projects list doesn't turn this
    /// card into its own scroll view — sorted ascending by completion so
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
                .foregroundStyle(Color.accentColor.gradient)
                .annotation(position: .trailing) {
                    Text(row.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXScale(domain: 0...1)
            .chartXAxis(.hidden)
            .frame(height: CGFloat(rows.count) * 32 + 16)
        }
    }

    private func taskList(title: String, tasks: [PCCTask], emptyText: String) -> some View {
        let sorted = tasks.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let capped = Array(sorted.prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            if capped.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(capped) { task in
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Text(task.title)
                            .lineLimit(1)
                        Spacer()
                        if let dueDate = task.dueDate {
                            Text(dueDate, style: .date)
                                .font(.caption)
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
            Text("On-time completion rate")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            if let rate = viewModel.taskCompletionRateWithinDeadline {
                Text(rate, format: .percent.precision(.fractionLength(0)))
                    .font(.title2.bold())
            } else {
                Text("Not enough data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Productivity card

    private var productivityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader("Productivity", systemImage: "bolt.fill")
                miniTimerContent
                Divider()
                workHoursContent
            }
        }
    }

    @ViewBuilder
    private var miniTimerContent: some View {
        if let activeTimer = timerViewModel.activeTimer {
            VStack(alignment: .leading, spacing: 8) {
                Text(timerContainerLabel(for: activeTimer))
                    .font(.subheadline.bold())
                TimelineView(.periodic(from: activeTimer.startDate, by: 1)) { context in
                    Text(Self.formattedElapsed(context.date.timeIntervalSince(activeTimer.startDate)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Button("Stop") {
                    Task { await timerViewModel.stop() }
                }
                .buttonStyle(.borderedProminent)
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
                        .foregroundStyle(kind == timerSelectedKind ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(kind == timerSelectedKind ? Color.primary.opacity(0.12) : Color.clear)
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
            Text("\(totalHours, specifier: "%.1f") hrs this week")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 100)
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
        amount.formatted(.currency(code: "USD"))
    }
}
