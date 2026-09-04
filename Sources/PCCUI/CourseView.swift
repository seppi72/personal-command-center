import SwiftUI

/// Minimal Mac/iOS screen for ticket #19, extended by ticket #20: lists
/// Courses, and supports creating and deleting one. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope (mirrors `WorkView`).
///
/// On the shared Liquid Glass system since issue #72 — a grid of
/// `CourseCard` bubbles (mirrors `CategoriesView`'s own
/// grid+expand shape), replacing the earlier chalkboard costume
/// (`ScreenTheme.chalkboard`, the dashed-rule `RosterRowModifier`) `git log`
/// on this file still shows. Tapping a card expands it into a centered
/// overlay revealing that Course's Tasks and Meetings; reaching
/// `CourseDetailView` to edit the Course or manage those in full moved to a
/// "Manage Course" link inside that overlay, since a single tap is now
/// spent on the expand gesture instead of navigating directly. The screen's
/// one surviving piece of "lecture hall" flavor is its typography — Course
/// titles set in a serif, the only screen in the app that uses one — now
/// that the chalkboard fill and dashed roster chrome are gone; the Term
/// badge survives too, redrawn as a glass well rather than a chalk ring.
///
/// The deleted `ClientsView`'s `ClientCard` (issue #69) briefly also set the Client
/// name and monogram seal in `design: .serif`, which would have made this
/// screen's "only screen" claim false — stripped back to the plain system
/// face there per issue #72's own acceptance criteria, so this screen keeps
/// the serif exclusively.
public struct CourseView: View {
    @ObservedObject private var viewModel: CoursesViewModel

    public init(viewModel: CoursesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CourseContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }

    /// e.g. "September 2026" — the Term's owner-facing rendering, shared by
    /// `CourseCard`'s caption (`CourseFormSheet` renders the same two
    /// fields as editable controls instead) and by `CourseDetailView`. Kept
    /// on this thin wrapper struct rather than on `CourseContent` since it
    /// has no environment dependency and outlives any one screen instance's
    /// theme.
    static func termLabel(month: Int, year: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        guard (1...12).contains(month), symbols.indices.contains(month - 1) else {
            return "\(month)/\(year)"
        }
        return "\(symbols[month - 1]) \(year)"
    }
}

/// This screen's one deliberate typographic signature — Course titles set
/// in a serif, kept local to this file rather than added to `PCCChassis`
/// since no other screen is meant to adopt it (per issue #72's acceptance
/// criteria).
private func courseTitleFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .serif)
}

/// The screen's actual content — split out from `CourseView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required, not optional —
/// `FinancesReportingView`/`FinancesReportingContent` hit this the hard
/// way first.
private struct CourseContent: View {
    @ObservedObject var viewModel: CoursesViewModel
    @State private var isPresentingNewCourseSheet = false

    /// Which card (if any) is currently expanded, and the `TasksViewModel`/
    /// `PersonalCommitmentsViewModel` scoped to it — tapping a collapsed
    /// grid card sets all three; tapping the scrim, the close button, or the
    /// same card again clears them. Mirrors `ProjectsContent`'s
    /// `expandedProjectID`/`expandedSprintsViewModel`, just with a second
    /// scoped view model since a Course's expanded card reveals both its
    /// Tasks and its Meetings.
    @State private var expandedCourseID: UUID?
    @State private var expandedTasksViewModel: TasksViewModel?
    @State private var expandedCommitmentsViewModel: PersonalCommitmentsViewModel?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.courses.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    courseScroll
                }
            }
            .background(GlassScreenBackground())
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

    /// A `ScrollView` of `CourseCard`s in a `LazyVGrid`, with a centered
    /// expand overlay above a dimmed scrim rather than something grown in
    /// place out of its source grid cell — the same shape, for the same two
    /// real-bug reasons, `CategoriesContent.categoryScroll`'s own doc
    /// comment records in full (`LazyVGrid` not honoring `zIndex` across
    /// its own cells, and a grown-in-place transition never actually
    /// reading as "growing").
    private var courseScroll: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusStrip
                    courseGrid
                }
                .padding(PCCChassis.outerMargin)
            }
            if let expandedCourseID, let course = course(withID: expandedCourseID),
                let tasksViewModel = expandedTasksViewModel,
                let commitmentsViewModel = expandedCommitmentsViewModel {
                expandedOverlay(course, tasksViewModel: tasksViewModel, commitmentsViewModel: commitmentsViewModel)
            }
        }
        // On the enclosing `ZStack`, not the conditional content itself, so
        // it governs the whole insert/remove transition below rather than
        // only in-place property changes.
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: expandedCourseID)
    }

    private func course(withID id: UUID) -> Course? {
        viewModel.courses.first { $0.id == id }
    }

    /// A tap on a collapsed card expands it — see
    /// `expandedOverlay(_:tasksViewModel:commitmentsViewModel:)` for where
    /// the expanded state actually renders. Deletion moved from the former
    /// `List`'s swipe-to-delete to a context menu, the same device
    /// `ProjectCard`/`ClientCard` already use for their own grid cells.
    private var courseGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            ForEach(viewModel.courses) { course in
                Button {
                    if expandedCourseID == course.id {
                        expandedCourseID = nil
                    } else {
                        expandedCourseID = course.id
                        expandedTasksViewModel = viewModel.makeTasksViewModel(for: course)
                        expandedCommitmentsViewModel = viewModel.makeCommitmentsViewModel(for: course)
                    }
                } label: {
                    CourseCard(course: course, isOverdue: Self.isOverdue(course), isExpanded: false)
                }
                .buttonStyle(CourseCardPressStyle())
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteCourse(course) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    /// The single floating, enlarged `CourseCard` for whichever Course is
    /// tapped, its Tasks and Meetings loaded into `tasksViewModel`/
    /// `commitmentsViewModel` as soon as it appears (`.task(id:)`, keyed on
    /// the Course's id) — a dimmed scrim behind it (tap to dismiss), a close
    /// button on the card itself, and a "Manage Course" link down to
    /// `CourseDetailView` now that a tap on the collapsed card spends itself
    /// on expanding rather than navigating (mirrors
    /// `ProjectsContent.expandedOverlay(_:sprintsViewModel:)`, with the pair
    /// of scoped view models swapped in for that screen's single
    /// `SprintsViewModel`).
    private func expandedOverlay(
        _ course: Course,
        tasksViewModel: TasksViewModel,
        commitmentsViewModel: PersonalCommitmentsViewModel
    ) -> some View {
        ZStack {
            // Its own opacity-only transition — kept separate from the
            // card's `.scale` transition below, same reasoning as
            // `ProjectsContent.expandedOverlay(_:sprintsViewModel:)`.
            Rectangle()
                .fill(scrimColor)
                .ignoresSafeArea()
                .onTapGesture { expandedCourseID = nil }
                .transition(.opacity)
            VStack(spacing: 14) {
                CourseCard(
                    course: course,
                    isOverdue: Self.isOverdue(course),
                    isExpanded: true,
                    tasks: tasksViewModel.tasks,
                    commitments: commitmentsViewModel.commitments
                )
                .background(bubbleShadow)
                .overlay(alignment: .topTrailing) {
                    Button {
                        expandedCourseID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
                NavigationLink {
                    CourseDetailView(
                        course: course,
                        viewModel: viewModel,
                        tasksViewModel: tasksViewModel,
                        commitmentsViewModel: commitmentsViewModel
                    )
                } label: {
                    Label("Manage Course", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
                .foregroundStyle(theme.accent(colorScheme))
            }
            .frame(maxWidth: 360)
            // Distinct identity per Course so switching which card is
            // expanded is a genuine remove-then-insert, and so `.task(id:)`
            // below re-fires for the newly expanded Course rather than
            // treating a swap as an in-place update of the same view.
            .id(course.id)
            .task(id: course.id) {
                async let tasksLoad: Void = tasksViewModel.load()
                async let commitmentsLoad: Void = commitmentsViewModel.load()
                _ = await (tasksLoad, commitmentsLoad)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .zIndex(1)
    }

    private var scrimColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.6 : 0.28)
    }

    /// A drop shadow behind the expanded card — kept off the shared
    /// `GlassBubble` itself (which the collapsed grid cells also use) since
    /// only the enlarged overlay instance needs the heavier "lifted toward
    /// the viewer" shadow.
    private var bubbleShadow: some View {
        RoundedRectangle(cornerRadius: GlassBubbleStyle.gridCell.cornerRadius, style: .continuous)
            .fill(Color.clear)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.16), radius: 26, x: 0, y: 14)
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
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
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
                .font(.headline)
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
/// (mirrors `ProjectFormSheet`). Left in the shared chassis look rather than
/// a bespoke glass re-theme — a `Form`'s native controls don't read as
/// "liquid glass" however they're dressed, so there's nothing this screen's
/// own device would add here (mirrors `AccountFormSheet`'s identical
/// reasoning); only its backdrop moves to `GlassScreenBackground()` via
/// `glassScreenBackground()`, per issue #72.
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
/// read-only at the top (editing reached via the toolbar's "Edit" button —
/// same `CourseFormSheet`/`onSave` wiring as before), a "Tasks" section
/// listing the Course's Tasks with add/edit/complete/delete — the
/// Course-scoped counterpart to `ProjectDetailView`'s "Sprints" section,
/// backed by the same `TasksViewModel`/`TaskFormSheet` the Work
/// screen uses (just scoped to this Course via
/// `CoursesViewModel.makeTasksViewModel(for:)`) rather than a separate,
/// duplicated row/form implementation — plus a "Meetings" section (ticket
/// #56) listing the Course's linked Personal Commitments the same way,
/// backed by `PersonalCommitmentsViewModel`/`PersonalCommitmentFormSheet`
/// scoped via `CoursesViewModel.makeCommitmentsViewModel(for:)`. Reached
/// from `CourseView`'s expanded-card overlay via its "Manage Course" link
/// (issue #72) rather than a direct card tap, since a tap on the collapsed
/// grid card now expands it instead.
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
                    .font(courseTitleFont(20))
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
        .glassScreenBackground()
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
                initialKind: task.kind,
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

/// The tap feedback every collapsed `CourseCard` button uses — a brief
/// press-down scale dip, the same device `ProjectCard`'s/`ClientCard`'s own
/// press style uses, scoped separately per screen rather than shared,
/// matching that type's own precedent.
private struct CourseCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Course card

/// One Course's card: the shared `GlassBubble` surface (`.gridCell` size)
/// with this screen's own content on it — the glass `TermBadge` well, the
/// Course's name set in a serif (`courseTitleFont`, this screen's one
/// typographic signature), its Term caption, and a due-date readout. Used
/// two ways: `isExpanded: false` as the plain collapsed grid cell, and
/// `isExpanded: true` as the single centered card
/// `CourseContent.expandedOverlay(_:tasksViewModel:commitmentsViewModel:)`
/// paints above a dimmed scrim, additionally passed that Course's `tasks`
/// and `commitments` to reveal (mirrors `ProjectCard`'s/`ClientCard`'s own
/// two-ways-used shape).
private struct CourseCard: View {
    let course: Course
    let isOverdue: Bool
    let isExpanded: Bool
    var tasks: [PCCTask] = []
    var commitments: [PersonalCommitment] = []

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let baseHeight: CGFloat = 150
    private static let style: GlassBubbleStyle = .gridCell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TermBadge(month: course.termMonth, year: course.termYear)
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(courseTitleFont(15))
                        .lineLimit(2)
                    Text(CourseView.termLabel(month: course.termMonth, year: course.termYear))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if let dueDate = course.dueDate {
                Text(dueDate, style: .date)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isOverdue ? theme.signalRed(colorScheme) : .secondary)
                    .padding(.top, 10)
            }
            if isExpanded {
                rosterSection
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: Self.baseHeight, alignment: .topLeading)
        .glassBubble(Self.style)
    }

    // MARK: Roster (expanded reveal)

    /// The expanded card's own content: the Course's Tasks and Meetings,
    /// compact — the roster the collapsed cell's Term badge only hints at.
    /// Mirrors `ProjectCard.sprintsSection`/`ClientCard.recentWork`, just
    /// two grouped lists instead of one, since a Course's detail screen has
    /// two sections to reflect here rather than one.
    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1)
                .opacity(0.7)
            rosterGroup(title: tasks.count == 1 ? "1 TASK" : "\(tasks.count) TASKS", isEmpty: tasks.isEmpty, emptyText: "No Tasks yet") {
                ForEach(tasks) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 11))
                            .strikethrough(task.isComplete)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let dueDate = task.dueDate {
                            Text(Self.dateFormatter.string(from: dueDate))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            rosterGroup(
                title: commitments.count == 1 ? "1 MEETING" : "\(commitments.count) MEETINGS",
                isEmpty: commitments.isEmpty,
                emptyText: "No Meetings yet"
            ) {
                ForEach(commitments) { commitment in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(commitment.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.timeFormatter.string(from: commitment.startDate))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rosterGroup<Rows: View>(
        title: String, isEmpty: Bool, emptyText: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            if isEmpty {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                rows()
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// This screen's signature device, surviving the move off chalkboard: a
/// term-code well — cut from the same glass as the card behind it
/// (`GlassBubble.tint(for:)`/`.rimColor`, the same device `AccountsView`'s
/// own round type-icon well and `ClientCard`'s monogram seal use) rather
/// than the earlier dashed chalk-ring, so the Term badge stays a real
/// device without depending on chalkboard texture.
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
