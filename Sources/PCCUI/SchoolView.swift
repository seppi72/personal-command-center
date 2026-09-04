import SwiftUI

/// The School dashboard (issue #90) — the screen the Courses screen became,
/// having also absorbed the Course-scoped slice of Tasks and Time Entries.
///
/// Deliberately *not* the Work screen's layout (issue #89). Work asks "where
/// did my hours go" and answers it with a container tree and a stack of
/// totals; School asks "what is due, and where do I need to be", which is a
/// deadline-ordered list and a schedule rail. Forcing one component to render
/// both questions produces a worse version of each, so the two screens share
/// the glass chassis and nothing else — no tree here, and no KPI row there.
///
/// The one piece of the old Courses screen kept intact is its typography:
/// Course names still set in a serif, the only screen in the app that uses
/// one, and the `TermBadge` well below.
public struct SchoolView: View {
    @ObservedObject private var viewModel: SchoolViewModel

    public init(viewModel: SchoolViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SchoolContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// This screen's one deliberate typographic signature — Course titles set in
/// a serif, carried over from the deleted `CourseView` and kept local to this
/// file rather than added to `PCCChassis`, since no other screen is meant to
/// adopt it (per issue #72's acceptance criteria).
private func courseTitleFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .serif)
}

/// Which sheet the screen currently has open. One `Identifiable` enum rather
/// than a `@State` boolean per sheet — they're mutually exclusive, and an
/// enum makes that a fact of the type rather than a rule the flags have to
/// keep between them (mirrors `WorkSheet`).
private enum SchoolSheet: Identifiable {
    case newCourse
    case editCourse(Course)
    case newProject(courseID: UUID)
    case editProject(Project)
    case newTask(courseID: UUID?, projectID: UUID?)
    case editTask(PCCTask)
    case newMeeting(courseID: UUID)
    case editMeeting(PersonalCommitment)

    var id: String {
        switch self {
        case .newCourse: return "newCourse"
        case .editCourse(let course): return "editCourse:\(course.id)"
        case .newProject(let courseID): return "newProject:\(courseID)"
        case .editProject(let project): return "editProject:\(project.id)"
        case .newTask(let courseID, let projectID):
            return "newTask:\(courseID?.uuidString ?? "-"):\(projectID?.uuidString ?? "-")"
        case .editTask(let task): return "editTask:\(task.id)"
        case .newMeeting(let courseID): return "newMeeting:\(courseID)"
        case .editMeeting(let commitment): return "editMeeting:\(commitment.id)"
        }
    }
}

/// The screen's actual content — split out from `SchoolView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment in
/// `PCCChassis.swift` for why the split is required, not optional.
private struct SchoolContent: View {
    @ObservedObject var viewModel: SchoolViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    @State private var sheet: SchoolSheet?

    private static let railWidth: CGFloat = 300

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.courses.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    board
                }
            }
            .background(GlassScreenBackground())
            .navigationTitle("School")
            .toolbar { toolbarContent }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $sheet) { sheetContent($0) }
            .errorAlert($viewModel.errorMessage)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let course = viewModel.selectedCourse {
            ToolbarItem {
                Menu {
                    Button("New Task") { sheet = .newTask(courseID: course.id, projectID: nil) }
                    Button("New Project") { sheet = .newProject(courseID: course.id) }
                    Button("New Meeting") { sheet = .newMeeting(courseID: course.id) }
                } label: {
                    Label("Add to Course", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { sheet = .editCourse(course) } label: {
                    Label("Edit Course", systemImage: "slider.horizontal.3")
                }
            }
        }
        ToolbarItem {
            Button { sheet = .newCourse } label: {
                Label("New Course", systemImage: "graduationcap")
            }
        }
    }

    // MARK: - Board

    private var board: some View {
        VStack(spacing: 0) {
            rangeBar
                .padding(.horizontal, PCCChassis.outerMargin)
                .padding(.top, PCCChassis.outerMargin)
                .padding(.bottom, 14)
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        tileRow
                        if let course = viewModel.selectedCourse {
                            courseDetail(course)
                        } else {
                            courseGrid
                        }
                        priorityList
                    }
                    .padding(.horizontal, PCCChassis.outerMargin)
                    .padding(.bottom, PCCChassis.outerMargin)
                }
                Rectangle()
                    .fill(theme.panelLine(colorScheme))
                    .frame(width: 1)
                scheduleRail
            }
        }
    }

    /// Today / Week / Month with previous-next arrows — the same stepper the
    /// Work screen uses — plus the "This Term" preset, which resolves the
    /// Courses' own Term to that month's window (see
    /// `SchoolViewModel.selectCurrentTerm`). Stepping changes the tiles and
    /// the drill-down's hours; it never changes the Priority list or the
    /// schedule rail, both of which answer "now" rather than "in this
    /// window".
    private var rangeBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $viewModel.range.unit) {
                ForEach(WorkRangeUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            Button { viewModel.range.step(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.pccControlChip)
            Text(viewModel.range.title())
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 130)
            Button { viewModel.range.step(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.pccControlChip)
            if let term = viewModel.currentTerm {
                Button("This Term") { viewModel.selectCurrentTerm() }
                    .buttonStyle(.pccControlChip)
                    .help("Jump to \(term.label)")
            }
            Spacer()
        }
    }

    // MARK: - Tiles

    /// The four KPI figures. Only figures the model can actually produce —
    /// GPA, Credits Earned and Study Streak are absent rather than rendered
    /// as placeholder numbers, and stay absent until the data behind them
    /// exists (issue #92). Tiles render zeroed rather than hidden, so the row
    /// doesn't reflow once data arrives.
    private var tileRow: some View {
        let tiles = viewModel.tiles
        return HStack(spacing: 14) {
            tile(
                "Assignments Left", value: "\(tiles.assignmentsLeft)",
                caption: "\(tiles.assignmentsDueInRange) due \(rangeCaption)",
                status: tiles.assignmentsDueInRange > 0 ? .attention : .nominal)
            tile(
                "Hours Logged", value: PCCDuration.stamp(tiles.loggedSeconds),
                caption: rangeCaption.capitalizedFirst, status: .active)
            tile(
                "Deadlines", value: "\(tiles.deadlinesInRange)", caption: rangeCaption.capitalizedFirst,
                status: tiles.deadlinesInRange > 0 ? .attention : .nominal)
            tile(
                "Active Courses", value: "\(tiles.activeCourses)",
                caption: viewModel.currentTerm?.label ?? "No Term",
                status: .nominal)
        }
    }

    /// The range in the voice a tile subtitle needs — "this week", "in March
    /// 2026" — since "3 due This Week" reads wrong beside a figure.
    ///
    /// Keyed off the range's own `unit`/`offset` rather than off the string
    /// `WorkDateRange.title()` renders: matching on that text would silently
    /// start reading "in This Week" the day someone rewords the stepper's
    /// label.
    private var rangeCaption: String {
        let range = viewModel.range
        // The windows whose titles are already an adverbial phrase ("This
        // Week") only need lowercasing; every other title is a bare date and
        // needs the preposition.
        guard (-1...0).contains(range.offset) else { return "in \(range.title())" }
        return range.title().lowercased()
    }

    private func tile(_ label: String, value: String, caption: String, status: PanelStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(status)
                Text(label)
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.pccReadout(26))
                .foregroundStyle(theme.accent(colorScheme))
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
    }

    // MARK: - Courses

    /// The Course cards. Tapping one drills into it — the detail replaces
    /// this grid in place rather than floating above it in an overlay the way
    /// the deleted `CourseView` did: the drill-down is a working surface with
    /// four sections on it, not a peek at a card's contents.
    private var courseGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Courses")
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14
            ) {
                ForEach(viewModel.courses) { course in
                    Button {
                        viewModel.selectedCourseID = course.id
                    } label: {
                        courseCard(course)
                    }
                    .buttonStyle(CourseCardPressStyle())
                    .contextMenu {
                        Button("Edit Course") { sheet = .editCourse(course) }
                        Button("Delete Course", role: .destructive) {
                            Task { await viewModel.deleteCourse(course) }
                        }
                    }
                }
            }
        }
    }

    private func courseCard(_ course: Course) -> some View {
        let open = viewModel.tasks(for: course).filter { !$0.isComplete }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TermBadge(month: course.termMonth, year: course.termYear)
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(courseTitleFont(15))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(SchoolTerm(course).label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Text(open == 1 ? "1 OPEN" : "\(open) OPEN")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let dueDate = course.dueDate {
                    Text(Self.dayFormatter.string(from: dueDate))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isOverdue(course) ? theme.signalRed(colorScheme) : .secondary)
                }
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .glassBubble(.gridCell)
    }

    private func isOverdue(_ course: Course) -> Bool {
        guard let dueDate = course.dueDate else { return false }
        return dueDate < Date()
    }

    // MARK: - Course drill-down

    /// One Course in full: its Projects, its Tasks, its Deadlines and its
    /// logged hours. The only place Course-owned Projects surface anywhere in
    /// the app — the Work screen filters them out of its own tree (issue
    /// #88) — and deliberately a flat set of sections rather than a tree,
    /// since a Course's depth stops at Project.
    private func courseDetail(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    viewModel.selectedCourseID = nil
                } label: {
                    Label("All Courses", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.pccControlChip)
                TermBadge(month: course.termMonth, year: course.termYear)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(courseTitleFont(20))
                    Text(SchoolTerm(course).label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Hours \(rangeCaption.capitalizedFirst)")
                        .pccPanelLabel()
                        .foregroundStyle(.secondary)
                    Text(PCCDuration.stamp(viewModel.loggedSeconds(for: course)))
                        .font(.pccReadout(20))
                        .foregroundStyle(theme.accent(colorScheme))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBubble()

            detailSection("Projects", isEmpty: viewModel.projects(for: course).isEmpty, emptyText: "No Projects in this Course.") {
                ForEach(viewModel.projects(for: course)) { project in
                    detailRow(
                        title: project.name, subtitle: projectSubtitle(project, in: course),
                        trailing: project.dueDate.map(Self.dayFormatter.string(from:))
                    )
                    .contextMenu {
                        Button("New Task in Project") {
                            sheet = .newTask(courseID: nil, projectID: project.id)
                        }
                        Button("Edit Project") { sheet = .editProject(project) }
                        Button("Delete Project", role: .destructive) {
                            Task { await viewModel.deleteProject(project) }
                        }
                    }
                }
            }

            detailSection("Tasks", isEmpty: viewModel.tasks(for: course).isEmpty, emptyText: "No Tasks in this Course.") {
                ForEach(viewModel.tasks(for: course)) { task in
                    taskRow(task)
                }
            }

            detailSection("Deadlines", isEmpty: viewModel.deadlines(for: course).isEmpty, emptyText: "Nothing dated in this Course.") {
                ForEach(viewModel.deadlines(for: course)) { item in
                    detailRow(
                        title: item.title, subtitle: item.kind.rawValue.capitalized,
                        trailing: item.dueDate.map(Self.dayFormatter.string(from:)),
                        trailingIsOverdue: DeadlinesViewModel.isOverdue(item))
                }
            }

            detailSection("Meetings", isEmpty: viewModel.commitments(for: course).isEmpty, emptyText: "No Meetings in this Course.") {
                ForEach(viewModel.commitments(for: course)) { commitment in
                    detailRow(
                        title: commitment.title,
                        subtitle: "\(Self.dayFormatter.string(from: commitment.startDate))   ·   \(Self.timeFormatter.string(from: commitment.startDate))–\(Self.timeFormatter.string(from: commitment.endDate))",
                        trailing: commitment.recurrenceRule
                    )
                    .contextMenu {
                        Button("Edit Meeting") { sheet = .editMeeting(commitment) }
                        Button("Delete Meeting", role: .destructive) {
                            Task { await viewModel.deleteCommitment(commitment) }
                        }
                    }
                }
            }
        }
    }

    /// "4 Tasks · 2 open" — what a Project row says about itself, since a
    /// Course-owned Project has no other summary on this screen.
    private func projectSubtitle(_ project: Project, in course: Course) -> String {
        let filed = viewModel.tasks(for: course).filter { $0.projectID == project.id }
        let open = filed.filter { !$0.isComplete }.count
        return "\(filed.count) \(filed.count == 1 ? "Task" : "Tasks")   ·   \(open) open"
    }

    @ViewBuilder
    private func detailSection<Rows: View>(
        _ title: String, isEmpty: Bool, emptyText: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            if isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                rows()
            }
        }
    }

    private func detailRow(
        title: String, subtitle: String?, trailing: String?, trailingIsOverdue: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(trailingIsOverdue ? theme.signalRed(colorScheme) : .secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
    }

    /// A Task row with its completion toggle — the drill-down's Tasks
    /// section, where a Task can still be ticked off even though the Priority
    /// list above drops completed ones.
    private func taskRow(_ task: PCCTask) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.setTaskCompletion(task, isComplete: !task.isComplete) }
            } label: {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isComplete ? theme.signalGreen(colorScheme) : Color.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .strikethrough(task.isComplete)
                if let kind = task.kind, !kind.isEmpty {
                    Text(kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let dueDate = task.dueDate {
                Text(Self.dayFormatter.string(from: dueDate))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
        .contextMenu { taskMenu(task) }
    }

    // MARK: - Priority Tasks

    /// Open Course Tasks in Deadline proximity order — overdue first, undated
    /// last, the same rule the Deadlines screen uses rather than a second
    /// competing notion of priority (see `SchoolBoard.priorityTasks`).
    /// Completed items drop off rather than lingering struck through.
    private var priorityList: some View {
        let items = viewModel.priorityTasks
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.selectedCourse == nil ? "Priority Tasks" : "Priority Tasks in this Course")
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("Nothing outstanding. Every Course Task is done.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(items) { item in
                    priorityRow(item)
                }
            }
        }
    }

    private func priorityRow(_ item: SchoolPriorityTask) -> some View {
        let countdown = DeadlinesViewModel.countdown(
            for: DeadlineItem(
                kind: .task, id: item.task.id, title: item.task.title, dueDate: item.task.dueDate,
                isComplete: item.task.isComplete))
        return HStack(spacing: 14) {
            Button {
                Task { await viewModel.setTaskCompletion(item.task, isComplete: true) }
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.task.title)
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    if let courseName = item.courseName {
                        chip(courseName, systemImage: "graduationcap")
                    }
                    if let projectName = item.projectName {
                        chip(projectName, systemImage: "folder")
                    }
                    if let kind = item.task.kind, !kind.isEmpty {
                        chip(kind, systemImage: "tag")
                    }
                }
            }
            Spacer(minLength: 8)
            if let countdown {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(countdown.numberText)
                        .font(.pccReadout(15))
                        .foregroundStyle(countdown.status.color(for: colorScheme, theme: theme))
                    Text(countdown.unitText.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("UNDATED")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble()
        .contextMenu { taskMenu(item.task) }
    }

    @ViewBuilder
    private func taskMenu(_ task: PCCTask) -> some View {
        Button("Edit Task") { sheet = .editTask(task) }
        Button(task.isComplete ? "Mark Incomplete" : "Mark Complete") {
            Task { await viewModel.setTaskCompletion(task, isComplete: !task.isComplete) }
        }
        Button("Delete Task", role: .destructive) {
            Task { await viewModel.deleteTask(task) }
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(.secondary)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.panelLine(colorScheme).opacity(0.55))
        )
    }

    // MARK: - Today's Schedule

    /// Today's Course-linked Commitments — which is where exams and quizzes
    /// appear, since those are Commitments rather than Tasks — plus any
    /// Course time logged today. Mirrored Calendar events are deliberately
    /// excluded: the Calendar is a mirror of an external system whose events
    /// aren't necessarily school-related, and they keep their own screen.
    private var scheduleRail: some View {
        let items = viewModel.todaySchedule
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today's Schedule")
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
                Text(Self.fullDayFormatter.string(from: Date()))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if items.isEmpty {
                    Text("Nothing scheduled today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(items) { item in
                        scheduleRow(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PCCChassis.outerMargin)
        }
        .frame(width: Self.railWidth)
    }

    private func scheduleRow(_ item: SchoolScheduleItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(item.kind == .runningTimer ? .active : .nominal)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(scheduleSubtitle(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let courseName = item.courseName, item.kind == .meeting {
                    Text(courseName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBubble(.gridCell)
    }

    private func scheduleSubtitle(_ item: SchoolScheduleItem) -> String {
        let start = Self.timeFormatter.string(from: item.startDate)
        guard let endDate = item.endDate else { return "\(start) – running" }
        return "\(start)–\(Self.timeFormatter.string(from: endDate))"
    }

    // MARK: - Empty state

    /// One call to action: with no Courses there is nothing to total, order,
    /// or schedule either. The tiles are absent here rather than zeroed —
    /// they render zeroed once a Course exists but has no work yet, which is
    /// the case the ticket's "tiles render zeroed rather than hidden" is
    /// about.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No Courses Yet")
                .font(courseTitleFont(18))
            Text("Create a Course to start tracking coursework.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Course") { sheet = .newCourse }
                .buttonStyle(.borderedProminent)
        }
        .padding(PCCChassis.outerMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: SchoolSheet) -> some View {
        switch sheet {
        case .newCourse:
            CourseFormSheet(
                title: "New Course", initialName: "",
                initialTermMonth: Calendar.current.component(.month, from: Date()),
                initialTermYear: Calendar.current.component(.year, from: Date()),
                initialDueDate: nil
            ) { values in
                await viewModel.createCourse(values)
            }
        case .editCourse(let course):
            CourseFormSheet(
                title: "Edit Course", initialName: course.name,
                initialTermMonth: course.termMonth, initialTermYear: course.termYear,
                initialDueDate: course.dueDate
            ) { values in
                await viewModel.updateCourse(course, with: values)
            }
        case .newProject(let courseID):
            ProjectFormSheet(title: "New Project", initialName: "", initialDueDate: nil) { values in
                await viewModel.createProject(courseID: courseID, values)
            }
        case .editProject(let project):
            ProjectFormSheet(
                title: "Edit Project", initialName: project.name, initialDueDate: project.dueDate
            ) { values in
                await viewModel.updateProject(project, with: values)
            }
        case .newTask(let courseID, let projectID):
            TaskFormSheet(
                title: "New Task", initialTitle: "", initialNotes: "",
                initialProjectID: projectID, initialCourseID: courseID, initialDueDate: nil,
                projects: courseProjects, courses: viewModel.courses
            ) { values in
                await viewModel.createTask(values)
            }
        case .editTask(let task):
            TaskFormSheet(
                title: "Edit Task", initialTitle: task.title, initialNotes: task.notes ?? "",
                initialProjectID: task.projectID, initialCourseID: task.courseID,
                initialKind: task.kind, initialDueDate: task.dueDate,
                projects: courseProjects, courses: viewModel.courses
            ) { values in
                await viewModel.updateTask(task, with: values)
            }
        case .newMeeting(let courseID):
            PersonalCommitmentFormSheet(
                title: "New Meeting",
                initialValues: PersonalCommitmentFormValues(
                    title: "", startDate: Date(), endDate: Date().addingTimeInterval(3600),
                    courseID: courseID),
                courses: viewModel.courses
            ) { values in
                await viewModel.createCommitment(values)
            }
        case .editMeeting(let commitment):
            PersonalCommitmentFormSheet(
                title: "Edit Meeting",
                initialValues: PersonalCommitmentFormValues(
                    title: commitment.title, startDate: commitment.startDate,
                    endDate: commitment.endDate, recurrenceRule: commitment.recurrenceRule,
                    courseID: commitment.courseID),
                courses: viewModel.courses
            ) { values in
                await viewModel.updateCommitment(commitment, with: values)
            }
        }
    }

    /// Only Course-owned Projects reach this screen's pickers — a Client's
    /// Project belongs to the Work screen, and offering one here would let a
    /// Task be filed out of School entirely by accident.
    private var courseProjects: [Project] {
        viewModel.projects.filter { $0.courseID != nil }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

extension String {
    /// "this week" → "This week", for a caption reused mid-sentence and at
    /// the head of one. Not `capitalized`, which would also lower-case the
    /// rest and turn "in March 2026" into "In march 2026".
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// The tap feedback every Course card uses — a brief press-down scale dip,
/// carried over from the deleted `CourseView` and kept scoped to this screen
/// rather than shared, matching that type's own precedent.
private struct CourseCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shared create/edit form: the same sheet serves "New Course" and "Edit
/// Course" — a name field, Term (month/year) fields, and a Deadline toggle
/// (mirrors `ProjectFormSheet`). Folded in from the deleted `CourseView`
/// unchanged. Left in the shared chassis look rather than a bespoke glass
/// re-theme — a `Form`'s native controls don't read as "liquid glass" however
/// they're dressed, so there's nothing this screen's own device would add here
/// (mirrors `AccountFormSheet`'s identical reasoning); only its backdrop moves
/// to `GlassScreenBackground()` via `glassScreenBackground()`, per issue #72.
struct CourseFormSheet: View {
    let title: String
    let onSave: (CourseFormValues) async -> Void

    @State private var name: String
    @State private var termMonth: Int
    @State private var termYear: Int
    @State private var hasDeadline: Bool
    @State private var dueDate: Date
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialName: String,
        initialTermMonth: Int,
        initialTermYear: Int,
        initialDueDate: Date?,
        onSave: @escaping (CourseFormValues) async -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
        self._termMonth = State(initialValue: initialTermMonth)
        self._termYear = State(initialValue: initialTermYear)
        self._hasDeadline = State(initialValue: initialDueDate != nil)
        self._dueDate = State(initialValue: initialDueDate ?? Date())
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` unless the "Has deadline" toggle is on — SwiftUI's `DatePicker`
    /// has no built-in optional-date mode, so the toggle stands in for one
    /// (mirrors `ProjectFormSheet.selectedDueDate`).
    private var selectedDueDate: Date? {
        hasDeadline ? dueDate : nil
    }

    private static let monthSymbols = Calendar.current.monthSymbols

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .pccField()
                }
                .panelRows()
                Section("Term") {
                    PCCMenuPicker(
                        "Month", selection: $termMonth,
                        options: (1...12).map { ($0, Self.monthSymbols[$0 - 1]) }
                    )
                    Stepper("Year: \(termYear)", value: $termYear, in: 1900...3000)
                }
                .panelRows()
                Section("Deadline") {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
                .panelRows()
            }
            .glassScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = CourseFormValues(
                            name: trimmedName, termMonth: termMonth, termYear: termYear,
                            dueDate: selectedDueDate)
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}

/// This screen's signature device, carried over intact from the deleted
/// `CourseView`: a term-code well — cut from the same glass as the card
/// behind it (`GlassBubble.tint(for:)`/`.rimColor`, the same device
/// `AccountsView`'s own round type-icon well uses) rather than the
/// chalkboard-era dashed chalk ring, so the Term badge stays a real device
/// without depending on chalkboard texture.
private struct TermBadge: View {
    let month: Int
    let year: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(GlassBubble.tint(for: colorScheme)))
            .overlay(
                Circle().strokeBorder(GlassBubble.rimColor(theme, colorScheme), lineWidth: GlassBubble.rimWidth)
            )
            .overlay(
                Text(code)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent(colorScheme))
            )
            .frame(width: 42, height: 42)
    }

    /// e.g. "FA26" — a lecture-hall room-plate-style short code (season +
    /// 2-digit year) standing in for the full Term caption shown beside it,
    /// so the badge reads at a glance instead of repeating text.
    private var code: String {
        "\(seasonCode)\(String(format: "%02d", year % 100))"
    }

    private var seasonCode: String {
        switch month {
        case 12, 1, 2: return "WI"
        case 3...5: return "SP"
        case 6...8: return "SU"
        case 9...11: return "FA"
        default: return "TM"
        }
    }
}
