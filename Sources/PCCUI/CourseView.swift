import SwiftUI

/// Minimal Mac/iOS screen for ticket #19, extended by ticket #20: lists
/// Courses, and supports creating and deleting one. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope (mirrors `ProjectsView`). Tapping a row navigates into
/// `CourseDetailView` (ticket #20) rather than opening the edit sheet
/// directly — editing moved to that screen's own toolbar, the same
/// evolution `ProjectsView` went through in ticket #18 once it needed to
/// show a Project's Sprints.
public struct CourseView: View {
    @ObservedObject private var viewModel: CoursesViewModel

    public init(viewModel: CoursesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CourseContent(viewModel: viewModel)
            .screenTheme(.chalkboard)
    }

    /// e.g. "September 2026" — the Term's owner-facing rendering, shared by
    /// the row caption in `CourseContent` (`CourseFormSheet` renders the
    /// same two fields as editable controls instead) and by
    /// `CourseDetailView`. Kept on this thin wrapper struct rather than on
    /// `CourseContent` since it has no environment dependency and outlives
    /// any one screen instance's theme.
    static func termLabel(month: Int, year: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        guard (1...12).contains(month), symbols.indices.contains(month - 1) else {
            return "\(month)/\(year)"
        }
        return "\(symbols[month - 1]) \(year)"
    }
}

/// The screen's actual content — split out from `CourseView` itself so
/// `.screenTheme(.chalkboard)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct CourseContent: View {
    @ObservedObject var viewModel: CoursesViewModel
    @State private var isPresentingNewCourseSheet = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.courses.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    courseList
                }
            }
            .navigationTitle("Courses")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewCourseSheet = true
                    } label: {
                        Label("Add Course", systemImage: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Error", isPresented: isShowingError, presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $isPresentingNewCourseSheet) {
                CourseFormSheet(
                    title: "New Course",
                    initialName: "",
                    initialTermMonth: Calendar.current.component(.month, from: Date()),
                    initialTermYear: Calendar.current.component(.year, from: Date()),
                    initialDueDate: nil
                ) { values in
                    await viewModel.createCourse(values)
                }
            }
        }
    }

    private var courseList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.courses) { course in
                    NavigationLink {
                        CourseDetailView(
                            course: course,
                            viewModel: viewModel,
                            tasksViewModel: viewModel.makeTasksViewModel(for: course),
                            commitmentsViewModel: viewModel.makeCommitmentsViewModel(for: course)
                        )
                    } label: {
                        CourseRow(course: course, isOverdue: Self.isOverdue(course))
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { viewModel.courses[$0] }
                    Task {
                        for course in toDelete {
                            await viewModel.deleteCourse(course)
                        }
                    }
                }
                .rosterRows()
            }
        }
        .panelScreenBackground()
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(overallStatus)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
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

    private var overallStatus: PanelStatus {
        overdueCount > 0 ? .critical : .nominal
    }

    private var overdueCount: Int {
        viewModel.courses.filter(Self.isOverdue).count
    }

    private static func isOverdue(_ course: Course) -> Bool {
        guard let dueDate = course.dueDate else { return false }
        return dueDate < Date()
    }

    private var statusStripText: String {
        let count = viewModel.courses.count
        let noun = count == 1 ? "COURSE" : "COURSES"
        let flagText = overdueCount > 0 ? "\(overdueCount) OVERDUE" : "ON TRACK"
        return "\(count) \(noun)   ·   \(flagText)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Courses")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Tap + to create your first Course.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { viewModel.errorMessage = nil } }
        )
    }
}

/// Shared create/edit form: the same sheet serves "New Course" and "Edit
/// Course" — a name field, Term (month/year) fields, and a Deadline toggle
/// (mirrors `ProjectFormSheet`).
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
            .panelScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = CourseFormValues(
                            name: trimmedName,
                            termMonth: termMonth,
                            termYear: termYear,
                            dueDate: selectedDueDate
                        )
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

/// A Course's detail screen (ticket #20): the Course's name/Term/due date
/// read-only at the top (editing moved here from the list row, via the
/// toolbar's "Edit" button — same `CourseFormSheet`/`onSave` wiring as
/// before), a "Tasks" section listing the Course's Tasks with
/// add/edit/complete/delete — the Course-scoped counterpart to
/// `ProjectDetailView`'s "Sprints" section, backed by the same
/// `TasksViewModel`/`TaskFormSheet` the top-level Tasks screen uses (just
/// scoped to this Course via `CoursesViewModel.makeTasksViewModel(for:)`)
/// rather than a separate, duplicated row/form implementation — plus a
/// "Meetings" section (ticket #56) listing the Course's linked Personal
/// Commitments the same way, backed by `PersonalCommitmentsViewModel`/
/// `PersonalCommitmentFormSheet` scoped via
/// `CoursesViewModel.makeCommitmentsViewModel(for:)`.
struct CourseDetailView: View {
    let course: Course
    @ObservedObject var viewModel: CoursesViewModel
    @ObservedObject var tasksViewModel: TasksViewModel
    @ObservedObject var commitmentsViewModel: PersonalCommitmentsViewModel

    @State private var isPresentingEditSheet = false
    @State private var isPresentingNewTaskSheet = false
    @State private var editingTask: PCCTask?
    @State private var isPresentingNewMeetingSheet = false
    @State private var editingCommitment: PersonalCommitment?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    /// The freshest known copy of `course` — falls back to the value passed
    /// in if `viewModel.courses` hasn't (yet) reflected an edit.
    private var currentCourse: Course {
        viewModel.courses.first(where: { $0.id == course.id }) ?? course
    }

    var body: some View {
        List {
            Section {
                Text(currentCourse.name)
                    .font(.title3)
                Text(CourseView.termLabel(month: currentCourse.termMonth, year: currentCourse.termYear))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let dueDate = currentCourse.dueDate {
                    Text(dueDate, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .panelRows()
            Section("Tasks") {
                listRows(
                    items: tasksViewModel.tasks,
                    emptyText: "No Tasks yet.",
                    onDelete: { offsets in
                        let toDelete = offsets.map { tasksViewModel.tasks[$0] }
                        Task {
                            for task in toDelete {
                                await tasksViewModel.deleteTask(task)
                            }
                        }
                    }
                ) { task in
                    HStack {
                        Button {
                            Task {
                                await tasksViewModel.setCompletion(task, isComplete: !task.isComplete)
                            }
                        } label: {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isComplete ? theme.signalGreen(colorScheme) : Color.secondary)
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif

                        Button {
                            editingTask = task
                        } label: {
                            VStack(alignment: .leading) {
                                Text(task.title)
                                    .strikethrough(task.isComplete)
                                if let dueDate = task.dueDate {
                                    Text(dueDate, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                Button {
                    isPresentingNewTaskSheet = true
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
            }
            .panelRows()
            Section("Meetings") {
                listRows(
                    items: commitmentsViewModel.commitments,
                    emptyText: "No Meetings yet.",
                    onDelete: { offsets in
                        let toDelete = offsets.map { commitmentsViewModel.commitments[$0] }
                        Task {
                            for commitment in toDelete {
                                await commitmentsViewModel.deleteCommitment(commitment)
                            }
                        }
                    }
                ) { commitment in
                    Button {
                        editingCommitment = commitment
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commitment.title)
                            Text("\(commitment.startDate, style: .time) – \(commitment.endDate, style: .time)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let recurrenceRule = commitment.recurrenceRule {
                                Text(recurrenceRule)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
                Button {
                    isPresentingNewMeetingSheet = true
                } label: {
                    Label("Add Meeting", systemImage: "plus")
                }
            }
            .panelRows()
        }
        .panelScreenBackground()
        .navigationTitle(currentCourse.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isPresentingEditSheet = true
                }
            }
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .alert("Error", isPresented: isShowingTasksError, presenting: tasksViewModel.errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert("Error", isPresented: isShowingCommitmentsError, presenting: commitmentsViewModel.errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $isPresentingEditSheet) {
            CourseFormSheet(
                title: "Edit Course",
                initialName: currentCourse.name,
                initialTermMonth: currentCourse.termMonth,
                initialTermYear: currentCourse.termYear,
                initialDueDate: currentCourse.dueDate
            ) { values in
                await viewModel.updateCourse(currentCourse, with: values)
            }
        }
        .sheet(isPresented: $isPresentingNewTaskSheet) {
            TaskFormSheet(
                title: "New Task",
                initialTitle: "",
                initialNotes: "",
                initialProjectID: nil,
                initialCourseID: currentCourse.id,
                initialDueDate: nil,
                projects: tasksViewModel.projects,
                courses: tasksViewModel.courses
            ) { values in
                await tasksViewModel.createTask(values)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskFormSheet(
                title: "Edit Task",
                initialTitle: task.title,
                initialNotes: task.notes ?? "",
                initialProjectID: task.projectID,
                initialCourseID: task.courseID,
                initialDueDate: task.dueDate,
                projects: tasksViewModel.projects,
                courses: tasksViewModel.courses
            ) { values in
                await tasksViewModel.updateTask(task, with: values)
            }
        }
        .sheet(isPresented: $isPresentingNewMeetingSheet) {
            PersonalCommitmentFormSheet(
                title: "New Meeting",
                initialValues: PersonalCommitmentFormValues(
                    title: "", startDate: Date(), endDate: Date().addingTimeInterval(3600), courseID: currentCourse.id
                ),
                courses: commitmentsViewModel.courses
            ) { values in
                await commitmentsViewModel.createCommitment(values)
            }
        }
        .sheet(item: $editingCommitment) { commitment in
            PersonalCommitmentFormSheet(
                title: "Edit Meeting",
                initialValues: PersonalCommitmentFormValues(
                    title: commitment.title,
                    startDate: commitment.startDate,
                    endDate: commitment.endDate,
                    recurrenceRule: commitment.recurrenceRule,
                    courseID: commitment.courseID
                ),
                courses: commitmentsViewModel.courses
            ) { values in
                await commitmentsViewModel.updateCommitment(commitment, with: values)
            }
        }
    }

    private var isShowingTasksError: Binding<Bool> {
        Binding(
            get: { tasksViewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { tasksViewModel.errorMessage = nil } }
        )
    }

    private var isShowingCommitmentsError: Binding<Bool> {
        Binding(
            get: { commitmentsViewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { commitmentsViewModel.errorMessage = nil } }
        )
    }

    /// Loads the Tasks and Meetings sections concurrently — shared by
    /// `.task`/`.refreshable` so the two don't each repeat the same
    /// `async let` pair.
    private func loadAll() async {
        async let tasksLoad: Void = tasksViewModel.load()
        async let commitmentsLoad: Void = commitmentsViewModel.load()
        _ = await (tasksLoad, commitmentsLoad)
    }

    /// The "empty text, else a deletable list of rows" shape both the Tasks
    /// and Meetings sections share — `row` owns each item's own tap
    /// target(s) (Tasks needs two independent ones, a completion toggle
    /// plus edit; Meetings needs only one), so only the boilerplate around
    /// it — the empty state, `ForEach`, and swipe-to-delete — is factored
    /// out here.
    @ViewBuilder
    private func listRows<Item: Identifiable, Row: View>(
        items: [Item],
        emptyText: String,
        onDelete: @escaping (IndexSet) -> Void,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if items.isEmpty {
            Text(emptyText)
                .foregroundStyle(.secondary)
        } else {
            ForEach(items, content: row)
                .onDelete(perform: onDelete)
        }
    }
}

// MARK: - Chalkboard theme

extension ScreenTheme {
    /// `CourseView`'s own vibe: a lecture hall / chalkboard — cool ledger
    /// paper in Light Mode (greyer than Commitments' warm cream or
    /// Clients' ivory, so the three don't read as the same material), the
    /// chalkboard itself in Dark Mode — deep slate green with chalk-white
    /// ink — and a brass accent standing in for a chalk-holder or a
    /// lecture hall's brass fittings. Signal colors left as
    /// `ScreenTheme.default`'s.
    fileprivate static let chalkboard = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x1E2B23) : Color(hex: 0xF0EDE1) },
        panelSurface: { $0 == .dark ? Color(hex: 0x283A31) : Color(hex: 0xFAF8EE) },
        panelLine: { $0 == .dark ? Color(hex: 0x3B4F42) : Color(hex: 0xD6D0B8) },
        accent: { $0 == .dark ? Color(hex: 0xD9B36A) : Color(hex: 0x8A6A22) },
        signalGreen: ScreenTheme.default.signalGreen,
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: ScreenTheme.default.signalRed
    )
}

// MARK: - Roster row

/// This screen's own row chrome — no bordered card per row (every other
/// list-backed screen's `panelRows()`), just a dashed chalk-line under
/// each row, since the signature device here (`TermBadge`) already carries
/// the visual weight a card border would otherwise add. A local modifier
/// rather than a chassis-wide alternative to `panelRows()`, since only
/// this screen wants it — the roster look is this screen's own choice,
/// not a device other screens should default to.
extension View {
    fileprivate func rosterRows() -> some View {
        modifier(RosterRowModifier())
    }
}

private struct RosterRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .overlay(alignment: .bottom) {
                DashedLine()
                    .stroke(theme.panelLine(colorScheme), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: 1)
            }
    }
}

/// A single horizontal dashed rule — one continuous subpath (see
/// `View.screenTheme(_:)`'s sibling caution about multi-subpath `Shape`s
/// in `PCCChassis.swift`; this shape only ever has the one line, but kept
/// as a single `moveTo`/`addLine` pair on principle) rather than a plain
/// `Rectangle`, since `Rectangle` has no dash style to give it a chalk
/// texture.
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Course row

/// This screen's signature: a chalk-ring term badge — a dashed circle
/// standing in for a lecture-hall room plate — leading each row, with the
/// Course's name set in a rounded display face for a hand-chalk feel
/// without depending on an unreliable custom "Chalkboard" font (per
/// `PCCChassis.swift`'s own caution about `Font.custom` risking a silent
/// fallback). The due date, when present, gets a chalk-underline that
/// turns from brass to red once overdue.
private struct CourseRow: View {
    let course: Course
    let isOverdue: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            TermBadge(month: course.termMonth, year: course.termYear)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text(CourseView.termLabel(month: course.termMonth, year: course.termYear))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let dueDate = course.dueDate {
                    dueBadge(dueDate)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private func dueBadge(_ dueDate: Date) -> some View {
        Text("DUE \(Self.dueDateFormatter.string(from: dueDate).uppercased())")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(isOverdue ? theme.signalRed(colorScheme) : theme.accent(colorScheme))
            .padding(.bottom, 1)
            .overlay(
                Rectangle()
                    .fill(isOverdue ? theme.signalRed(colorScheme) : theme.panelLine(colorScheme))
                    .frame(height: 2),
                alignment: .bottom
            )
    }

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private struct TermBadge: View {
    let month: Int
    let year: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Circle()
            .strokeBorder(theme.accent(colorScheme), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            .frame(width: 46, height: 46)
            .overlay(
                Text(code)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent(colorScheme))
            )
    }

    /// e.g. "FA26" — a lecture-hall room-plate-style short code (season +
    /// 2-digit year) standing in for the full Term caption already shown
    /// below it, so the badge reads at a glance instead of repeating text.
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
