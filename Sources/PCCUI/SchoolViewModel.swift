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
/// could. It's also why this replaces the deleted `CoursesViewModel`'s
/// `makeTasksViewModel(for:)`/`makeCommitmentsViewModel(for:)` — the
/// drill-down reads the lists already here instead of standing up two more
/// view models per Course.
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
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var tasks: [PCCTask] = []
    @Published public private(set) var timeEntries: [TimeEntry] = []
    @Published public private(set) var commitments: [PersonalCommitment] = []
    /// Which Course the drill-down is open on, or `nil` for the whole-screen
    /// view. Kept as the id rather than the `Course` so a drill-down survives
    /// a reload that replaces the value.
    @Published public var selectedCourseID: UUID?
    @Published public var range = WorkDateRange()
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let coursesClient: CoursesAPIClient
    private let projectsClient: ProjectsAPIClient
    private let tasksClient: TasksAPIClient
    private let timeEntriesClient: TimeEntriesAPIClient
    private let commitmentsClient: PersonalCommitmentsAPIClient

    public init(
        coursesClient: CoursesAPIClient,
        projectsClient: ProjectsAPIClient,
        tasksClient: TasksAPIClient,
        timeEntriesClient: TimeEntriesAPIClient,
        commitmentsClient: PersonalCommitmentsAPIClient
    ) {
        self.coursesClient = coursesClient
        self.projectsClient = projectsClient
        self.tasksClient = tasksClient
        self.timeEntriesClient = timeEntriesClient
        self.commitmentsClient = commitmentsClient
    }

    // MARK: - Loading

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(noun: "School", verb: "load") {
            async let loadedCourses = coursesClient.listCourses()
            async let loadedProjects = projectsClient.listProjects()
            async let loadedTasks = tasksClient.listTasks(projectID: nil, courseID: nil)
            async let loadedEntries = timeEntriesClient.listTimeEntries(
                taskID: nil, projectID: nil, clientID: nil, courseID: nil)
            async let loadedCommitments = commitmentsClient.listPersonalCommitments(courseID: nil)
            courses = try await loadedCourses.sorted { $0.name < $1.name }
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

    /// The Term the "This Term" preset jumps to, and the label it carries —
    /// `nil` with no Courses, which is also when the preset is hidden.
    public var currentTerm: SchoolTerm? {
        SchoolBoard.currentTerm(in: courses)
    }

    /// Points `range` at the Term's own month-and-year window. Term stays a
    /// Course label: this resolves it to the existing `.month` unit at the
    /// right offset rather than adding a fourth `WorkRangeUnit`, which would
    /// also change the Work screen's stepper (issue #90).
    public func selectCurrentTerm(calendar: Calendar = .current, reference: Date = Date()) {
        guard let term = currentTerm else { return }
        let today = SchoolTerm.containing(reference, calendar: calendar)
        range = WorkDateRange(
            unit: .month,
            offset: (term.year - today.year) * 12 + (term.month - today.month))
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
        await run(noun: "Course", verb: "create") {
            var created = try await coursesClient.createCourse(
                name: values.name, termMonth: values.termMonth, termYear: values.termYear)
            if let dueDate = values.dueDate {
                created = try await coursesClient.setCourseDeadline(id: created.id, dueDate: dueDate)
            }
            courses.append(created)
            courses.sort { $0.name < $1.name }
        }
    }

    public func updateCourse(_ course: Course, with values: CourseFormValues) async {
        await run(noun: "Course", verb: "update") {
            var updated = try await coursesClient.updateCourse(
                id: course.id, name: values.name, termMonth: values.termMonth, termYear: values.termYear)
            if values.dueDate != course.dueDate {
                updated = try await coursesClient.setCourseDeadline(id: course.id, dueDate: values.dueDate)
            }
            if let index = courses.firstIndex(where: { $0.id == updated.id }) { courses[index] = updated }
            courses.sort { $0.name < $1.name }
        }
    }

    public func deleteCourse(_ course: Course) async {
        await run(noun: "Course", verb: "delete") {
            try await coursesClient.deleteCourse(id: course.id)
            courses.removeAll { $0.id == course.id }
            if selectedCourseID == course.id { selectedCourseID = nil }
        }
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
    private func run(noun: String, verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) \(noun): \(error.localizedDescription)"
        }
    }
}
