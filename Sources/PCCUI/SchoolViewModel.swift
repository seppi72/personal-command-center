import Foundation

/// Holds the School screen's state (issue #90) — the Courses, the
/// Course-scoped slice of Projects/Tasks/Time Entries/Commitments, the range
/// the figures are computed over, the drilled-into Course, and every CRUD
/// call the deleted Courses screen used to own.
///
/// Loads the flat lists once and derives every figure locally through
/// `SchoolBoard` rather than fetching per Course: this screen totals, orders
/// and counts the same data several ways at once, and one load plus pure
/// arithmetic can't disagree with itself the way several scoped fetches
/// could. It's also why the deleted `CoursesViewModel`'s per-Course view
/// model factories have no counterpart here — the drill-down reads the lists
/// already loaded instead of standing up two more view models per Course.
///
/// Client-side work is deliberately absent, the mirror of `WorkViewModel`
/// skipping Course-owned Projects: each dashboard owns one domain's hours,
/// and Overview is where the two are summed (issue #91).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class SchoolViewModel: ObservableObject {
    @Published public private(set) var courses: [Course] = []
    /// Every Term, earliest first — what the Course form's Term picker
    /// offers, and what the Terms sheet manages. Loaded alongside the
    /// Courses rather than fetched when a sheet opens, so a Course card and
    /// the picker behind it can't disagree about which Terms exist.
    @Published public private(set) var terms: [Term] = []
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var tasks: [PCCTask] = []
    @Published public private(set) var timeEntries: [TimeEntry] = []
    @Published public private(set) var commitments: [PersonalCommitment] = []
    /// The two academic figures, computed by the backend (issue #92) — the
    /// one part of this screen not derived locally through `SchoolBoard`,
    /// since the GWA rules have edge cases that deserve a single home
    /// (`SchoolSummary`). `nil` until the first load lands.
    @Published public private(set) var summary: SchoolSummary?
    /// Which Course the drill-down is open on, or `nil` for the whole-screen
    /// view. Kept as the id rather than the `Course` so a drill-down survives
    /// a reload that replaces the value.
    @Published public var selectedCourseID: UUID?
    @Published public var range = WorkDateRange()
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let coursesClient: CoursesAPIClient
    private let termsClient: TermsAPIClient
    private let projectsClient: ProjectsAPIClient
    private let tasksClient: TasksAPIClient
    private let timeEntriesClient: TimeEntriesAPIClient
    private let commitmentsClient: PersonalCommitmentsAPIClient
    private let reportingClient: SchoolReportingAPIClient

    public init(
        coursesClient: CoursesAPIClient,
        termsClient: TermsAPIClient,
        projectsClient: ProjectsAPIClient,
        tasksClient: TasksAPIClient,
        timeEntriesClient: TimeEntriesAPIClient,
        commitmentsClient: PersonalCommitmentsAPIClient,
        reportingClient: SchoolReportingAPIClient
    ) {
        self.coursesClient = coursesClient
        self.termsClient = termsClient
        self.projectsClient = projectsClient
        self.tasksClient = tasksClient
        self.timeEntriesClient = timeEntriesClient
        self.commitmentsClient = commitmentsClient
        self.reportingClient = reportingClient
    }

    // MARK: - Loading

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let didLoad = await run(noun: "School", verb: "load") {
            async let loadedCourses = coursesClient.listCourses()
            async let loadedTerms = termsClient.listTerms()
            async let loadedProjects = projectsClient.listProjects()
            async let loadedTasks = tasksClient.listTasks(projectID: nil, courseID: nil)
            async let loadedEntries = timeEntriesClient.listTimeEntries(
                taskID: nil, projectID: nil, clientID: nil, courseID: nil)
            async let loadedCommitments = commitmentsClient.listPersonalCommitments(courseID: nil)
            courses = try await loadedCourses.sorted { $0.name < $1.name }
            terms = try await loadedTerms
            projects = try await loadedProjects
            tasks = try await loadedTasks
            timeEntries = try await loadedEntries
            commitments = try await loadedCommitments
        }
        // A drill-down into a Course that's since been deleted returns to the
        // whole-screen view rather than showing an empty detail panel.
        if let id = selectedCourseID, !courses.contains(where: { $0.id == id }) {
            selectedCourseID = nil
        }
        await loadSummary(after: didLoad)
    }

    /// Fetches the GWA/Units Earned figures for the Term the Courses say is
    /// current. Runs after the lists rather than alongside them, because
    /// which Term to scope the per-Term GWA to is itself derived from the
    /// Courses just loaded (`SchoolBoard.currentTerm(in:)`).
    ///
    /// Refetched after any Course write too: a grade or unit change moves
    /// both figures, and a stale tile beside an edited Course card is a
    /// figure that disagrees with the data on the same screen.
    /// Callers pass the write's own outcome so a *failed* write doesn't
    /// refetch: `run` clears `errorMessage` on success, and refetching after
    /// a failure would wipe the message explaining why the write didn't
    /// happen. Keyed to that one call's result rather than to whatever
    /// `errorMessage` happens to hold, which could be a stale message from
    /// some earlier failure and would then suppress every refetch after it.
    private func loadSummary(after didSucceed: Bool) async {
        guard didSucceed else { return }
        await run(noun: "School figures", verb: "load") {
            summary = try await reportingClient.fetchSchoolSummary(termID: currentTerm?.id)
        }
    }

    // MARK: - Derived figures

    /// The four KPI tiles, over the current range.
    public var tiles: SchoolTiles {
        SchoolBoard.tiles(
            courses: courses, projects: projects, tasks: tasks, timeEntries: timeEntries,
            range: range.resolved())
    }

    /// The Priority Tasks list — every open Course Task when nothing is
    /// drilled into, narrowed to the drilled-into Course otherwise.
    public var priorityTasks: [SchoolPriorityTask] {
        let all = SchoolBoard.priorityTasks(tasks: tasks, courses: courses, projects: projects)
        guard let selectedCourseID else { return all }
        return all.filter { SchoolBoard.courseID(for: $0.task, projects: projects) == selectedCourseID }
    }

    /// Today's Schedule rail — Course meetings and Course time for today,
    /// regardless of the range. The rail answers "where do I need to be
    /// *now*", which stepping the range back a month doesn't change.
    public var todaySchedule: [SchoolScheduleItem] {
        SchoolBoard.todaySchedule(
            commitments: commitments, timeEntries: timeEntries, tasks: tasks,
            projects: projects, courses: courses)
    }

    /// The Course the drill-down is open on, or `nil`.
    public var selectedCourse: Course? {
        selectedCourseID.flatMap { id in courses.first { $0.id == id } }
    }

    /// The Term the "This Term" preset jumps to, and the name it carries —
    /// `nil` when no Course's Term has its dates filled in, which is also
    /// when the preset is hidden.
    public var currentTerm: Term? {
        SchoolBoard.currentTerm(in: courses)
    }

    /// Points `range` at the month the Term starts in. A Term now spans
    /// several months rather than being one (`docs/adr/0012-term-is-an-entity.md`),
    /// and `WorkDateRange` expresses only whole day/week/month windows — so
    /// the preset lands on the semester's opening month rather than adding a
    /// fourth `WorkRangeUnit`, which would also change the Work screen's
    /// stepper (issue #90).
    public func selectCurrentTerm(calendar: Calendar = .current, reference: Date = Date()) {
        guard let startDate = currentTerm?.startDate else { return }
        func startOfMonth(_ date: Date) -> Date {
            calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
        let months = calendar.dateComponents(
            [.month], from: startOfMonth(reference), to: startOfMonth(startDate)
        ).month ?? 0
        range = WorkDateRange(unit: .month, offset: months)
    }

    // MARK: - Course drill-down

    /// The drilled-into Course's own Projects — the only place Course-owned
    /// Projects surface anywhere in the app (the Work screen filters them
    /// out).
    public func projects(for course: Course) -> [Project] {
        projects.filter { $0.courseID == course.id }.sorted { $0.name < $1.name }
    }

    /// Every Task belonging to `course`, by either path — attached to it
    /// directly, or filed in one of its Projects.
    public func tasks(for course: Course) -> [PCCTask] {
        tasks.filter { SchoolBoard.courseID(for: $0, projects: projects) == course.id }
    }

    /// `course`'s Deadlines, in the same proximity order the Priority list
    /// uses — its own, its Projects', and its open Tasks'.
    public func deadlines(for course: Course) -> [DeadlineItem] {
        var items: [DeadlineItem] = []
        if course.dueDate != nil {
            items.append(DeadlineItem(kind: .course, id: course.id, title: course.name, dueDate: course.dueDate))
        }
        items += projects(for: course)
            .filter { $0.dueDate != nil }
            .map { DeadlineItem(kind: .project, id: $0.id, title: $0.name, dueDate: $0.dueDate) }
        items += tasks(for: course)
            .filter { $0.dueDate != nil && !$0.isComplete }
            .map {
                DeadlineItem(
                    kind: .task, id: $0.id, title: $0.title, dueDate: $0.dueDate,
                    isComplete: $0.isComplete)
            }
        return items.sorted {
            SchoolBoard.areInProximityOrder(($0.dueDate, $0.title), ($1.dueDate, $1.title))
        }
    }

    /// Seconds logged against `course` inside the current range — its share
    /// of the Hours Logged tile, and literally that tile's own function at a
    /// narrower scope, so the drill-down can't disagree with the figure above
    /// it.
    public func loggedSeconds(for course: Course) -> Double {
        SchoolBoard.loggedSeconds(
            courseID: course.id, tasks: tasks, projects: projects, timeEntries: timeEntries,
            range: range.resolved())
    }

    /// `course`'s class meetings, exams and quizzes, soonest first.
    public func commitments(for course: Course) -> [PersonalCommitment] {
        commitments.filter { $0.courseID == course.id }.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Courses

    /// Creates a Course with its name/Term and, if given, attaches its
    /// Deadline in a follow-up call — a Course is always created undated on
    /// the backend (`CourseController.create`), so a Deadline is a separate
    /// write (mirrors `WorkViewModel.createProject`).
    public func createCourse(_ values: CourseFormValues) async {
        let didWrite = await run(noun: "Course", verb: "create") {
            var created = try await coursesClient.createCourse(
                name: values.name, termID: values.termID, units: values.units, grade: values.grade)
            if let dueDate = values.dueDate {
                created = try await coursesClient.setCourseDeadline(id: created.id, dueDate: dueDate)
            }
            courses.append(created)
            courses.sort { $0.name < $1.name }
        }
        await loadSummary(after: didWrite)
    }

    public func updateCourse(_ course: Course, with values: CourseFormValues) async {
        let didWrite = await run(noun: "Course", verb: "update") {
            var updated = try await coursesClient.updateCourse(
                id: course.id, name: values.name, termID: values.termID, units: values.units,
                grade: values.grade)
            if values.dueDate != course.dueDate {
                updated = try await coursesClient.setCourseDeadline(id: course.id, dueDate: values.dueDate)
            }
            if let index = courses.firstIndex(where: { $0.id == updated.id }) { courses[index] = updated }
            courses.sort { $0.name < $1.name }
        }
        await loadSummary(after: didWrite)
    }

    public func deleteCourse(_ course: Course) async {
        let didWrite = await run(noun: "Course", verb: "delete") {
            try await coursesClient.deleteCourse(id: course.id)
            courses.removeAll { $0.id == course.id }
            if selectedCourseID == course.id { selectedCourseID = nil }
        }
        await loadSummary(after: didWrite)
    }

    // MARK: - Terms

    /// Creates a Term. The backend rejects a duplicate year-and-semester and
    /// a span overlapping another Term's (`TermController`), so a failure
    /// here surfaces its reason rather than being pre-empted client-side —
    /// one authority on what a legal Term is, not two that can drift.
    public func createTerm(_ values: TermFormValues) async {
        await run(noun: "Term", verb: "create") {
            let created = try await termsClient.createTerm(
                year: values.year, semester: values.semester, startDate: values.startDate,
                endDate: values.endDate)
            terms.append(created)
            terms.sort()
        }
    }

    /// Updates a Term, and refreshes the copy nested in every Course that
    /// belongs to it — a Course carries its whole Term, so leaving those
    /// stale would show the old name and dates until the next load.
    public func updateTerm(_ term: Term, with values: TermFormValues) async {
        await run(noun: "Term", verb: "update") {
            let updated = try await termsClient.updateTerm(
                id: term.id, year: values.year, semester: values.semester,
                startDate: values.startDate, endDate: values.endDate)
            if let index = terms.firstIndex(where: { $0.id == updated.id }) { terms[index] = updated }
            terms.sort()
            for index in courses.indices where courses[index].termID == updated.id {
                courses[index].term = updated
            }
        }
    }

    /// Deletes a Term. The backend blocks this while any Course still
    /// belongs to it, and that error is what the owner sees — deleting a
    /// Term must never take a semester of Courses with it.
    public func deleteTerm(_ term: Term) async {
        await run(noun: "Term", verb: "delete") {
            try await termsClient.deleteTerm(id: term.id)
            terms.removeAll { $0.id == term.id }
        }
    }

    /// How many Courses belong to `term` — what the Terms sheet shows beside
    /// each row, so it's clear before trying which Terms can still be
    /// deleted.
    public func courseCount(for term: Term) -> Int {
        courses.filter { $0.termID == term.id }.count
    }

    // MARK: - Course Projects

    /// Creates a Project and files it under `courseID` in a follow-up call —
    /// a Project is always created bare and unparented on the backend
    /// (`ProjectController.create`), so its Course parent and its Deadline
    /// are each a separate write (ticket #88).
    public func createProject(courseID: UUID, _ values: ProjectFormValues) async {
        await run(noun: "Project", verb: "create") {
            var created = try await projectsClient.createProject(name: values.name)
            created = try await projectsClient.setProjectCourse(id: created.id, courseID: courseID)
            if let dueDate = values.dueDate {
                created = try await projectsClient.setProjectDeadline(id: created.id, dueDate: dueDate)
            }
            projects.append(created)
        }
    }

    public func updateProject(_ project: Project, with values: ProjectFormValues) async {
        await run(noun: "Project", verb: "update") {
            var updated = try await projectsClient.updateProject(id: project.id, name: values.name)
            if values.dueDate != project.dueDate {
                updated = try await projectsClient.setProjectDeadline(id: project.id, dueDate: values.dueDate)
            }
            if let index = projects.firstIndex(where: { $0.id == updated.id }) { projects[index] = updated }
        }
    }

    public func deleteProject(_ project: Project) async {
        await run(noun: "Project", verb: "delete") {
            try await projectsClient.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
        }
    }

    // MARK: - Tasks

    /// Creates a Task and assigns its Course/Project/Deadline/Kind in
    /// follow-up calls — a Task is always created bare on the backend
    /// (`TaskController.create`), so each is a separate write (mirrors
    /// `WorkViewModel.createTask`). A Task filed in a Course-owned Project
    /// carries no `courseID` of its own: it reaches its Course through that
    /// Project, and the two are exclusive (ADR-0003).
    public func createTask(_ values: TaskFormValues) async {
        await run(noun: "Task", verb: "create") {
            var created = try await tasksClient.createTask(title: values.title, notes: values.notes)
            if let projectID = values.projectID {
                created = try await tasksClient.assignTaskProject(id: created.id, projectID: projectID)
            } else if let courseID = values.courseID {
                created = try await tasksClient.assignTaskCourse(id: created.id, courseID: courseID)
            }
            if let dueDate = values.dueDate {
                created = try await tasksClient.setTaskDeadline(id: created.id, dueDate: dueDate)
            }
            if let kind = values.kind {
                created = try await tasksClient.setTaskKind(id: created.id, kind: kind)
            }
            tasks.append(created)
        }
    }

    public func updateTask(_ task: PCCTask, with values: TaskFormValues) async {
        await run(noun: "Task", verb: "update") {
            var updated = try await tasksClient.updateTask(
                id: task.id, title: values.title, notes: values.notes)
            if values.projectID != task.projectID {
                updated = try await tasksClient.assignTaskProject(id: task.id, projectID: values.projectID)
            }
            if values.courseID != task.courseID {
                updated = try await tasksClient.assignTaskCourse(id: task.id, courseID: values.courseID)
            }
            if values.dueDate != task.dueDate {
                updated = try await tasksClient.setTaskDeadline(id: task.id, dueDate: values.dueDate)
            }
            if values.kind != task.kind {
                updated = try await tasksClient.setTaskKind(id: task.id, kind: values.kind)
            }
            replace(updated)
        }
    }

    public func setTaskCompletion(_ task: PCCTask, isComplete: Bool) async {
        await run(noun: "Task", verb: "update") {
            replace(try await tasksClient.setTaskCompletion(id: task.id, isComplete: isComplete))
        }
    }

    public func deleteTask(_ task: PCCTask) async {
        await run(noun: "Task", verb: "delete") {
            try await tasksClient.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
        }
    }

    private func replace(_ updated: PCCTask) {
        guard let index = tasks.firstIndex(where: { $0.id == updated.id }) else { return }
        tasks[index] = updated
    }

    // MARK: - Meetings

    public func createCommitment(_ values: PersonalCommitmentFormValues) async {
        await run(noun: "Meeting", verb: "create") {
            commitments.append(try await commitmentsClient.createPersonalCommitment(values))
        }
    }

    public func updateCommitment(_ commitment: PersonalCommitment, with values: PersonalCommitmentFormValues) async {
        await run(noun: "Meeting", verb: "update") {
            let updated = try await commitmentsClient.updatePersonalCommitment(id: commitment.id, values: values)
            if let index = commitments.firstIndex(where: { $0.id == updated.id }) { commitments[index] = updated }
        }
    }

    public func deleteCommitment(_ commitment: PersonalCommitment) async {
        await run(noun: "Meeting", verb: "delete") {
            try await commitmentsClient.deletePersonalCommitment(id: commitment.id)
            commitments.removeAll { $0.id == commitment.id }
        }
    }

    /// Runs a mutation, keeping every method's success/failure handling in
    /// one shape instead of a copy per method. Takes a `noun` as well as a
    /// `verb`, like `WorkViewModel.run(noun:verb:)` and unlike the
    /// single-noun view models: this screen mutates Courses, Projects, Tasks
    /// and Meetings, so "Couldn't create Task" has to name which.
    /// Returns whether the operation succeeded, so a caller with follow-up
    /// work (`loadSummary(after:)`) can skip it on failure rather than
    /// inspecting `errorMessage`, which may still hold an older message.
    @discardableResult
    private func run(noun: String, verb: String, _ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Couldn't \(verb) \(noun): \(error.localizedDescription)"
            return false
        }
    }
}
