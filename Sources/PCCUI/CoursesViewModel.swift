import Foundation

/// Holds the Courses screen's state and talks to the backend through a
/// `CoursesAPIClient`, plus a `TasksAPIClient`/`ProjectsAPIClient` to build
/// each Course's Tasks screen (`makeTasksViewModel(for:)`, ticket #20) and a
/// `PersonalCommitmentsAPIClient` to build its "Meetings" screen
/// (`makeCommitmentsViewModel(for:)`, ticket #56). Kept separate from
/// `CourseView` so the view stays a thin rendering of this state (mirrors
/// `WorkViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class CoursesViewModel: ObservableObject {
    @Published public private(set) var courses: [Course] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: CoursesAPIClient
    private let tasksClient: TasksAPIClient
    private let projectsClient: ProjectsAPIClient
    private let commitmentsClient: PersonalCommitmentsAPIClient

    public init(
        client: CoursesAPIClient,
        tasksClient: TasksAPIClient,
        projectsClient: ProjectsAPIClient,
        commitmentsClient: PersonalCommitmentsAPIClient
    ) {
        self.client = client
        self.tasksClient = tasksClient
        self.projectsClient = projectsClient
        self.commitmentsClient = commitmentsClient
    }

    /// Builds the `TasksViewModel` for one Course's detail screen, scoped to
    /// that Course's id — `CourseDetailView` needs a `TasksAPIClient`/
    /// `ProjectsAPIClient` and a `courseID`, and this is where all three are
    /// available together (mirrors `WorkViewModel.createSprint`,
    /// one level over).
    public func makeTasksViewModel(for course: Course) -> TasksViewModel {
        TasksViewModel(tasksClient: tasksClient, projectsClient: projectsClient, coursesClient: client, scopedCourseID: course.id)
    }

    /// Builds the `PersonalCommitmentsViewModel` for one Course's detail
    /// screen, scoped to that Course's id — `CourseDetailView`'s "Meetings"
    /// section (ticket #56), the same shape as `makeTasksViewModel(for:)`.
    public func makeCommitmentsViewModel(for course: Course) -> PersonalCommitmentsViewModel {
        PersonalCommitmentsViewModel(client: commitmentsClient, coursesClient: client, scopedCourseID: course.id)
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            courses = try await client.listCourses()
        }
    }

    /// Creates a Course with its name/Term and, if `values.dueDate` is
    /// given, attaches it in a follow-up call — a Course is always created
    /// undated on the backend (`CourseController.create`), so a Deadline is
    /// a separate write (mirrors `WorkViewModel.createProject`).
    public func createCourse(_ values: CourseFormValues) async {
        await run(verb: "create") {
            var created = try await client.createCourse(
                name: values.name,
                termMonth: values.termMonth,
                termYear: values.termYear
            )
            if let dueDate = values.dueDate {
                created = try await client.setCourseDeadline(id: created.id, dueDate: dueDate)
            }
            courses.append(created)
        }
    }

    /// Edits a Course's name/Term and, only if `values.dueDate` differs from
    /// `course`'s current one, updates its Deadline as a follow-up write —
    /// the same "write, then maybe update the rest" shape as `createCourse`.
    public func updateCourse(_ course: Course, with values: CourseFormValues) async {
        await run(verb: "update") {
            var updated = try await client.updateCourse(
                id: course.id,
                name: values.name,
                termMonth: values.termMonth,
                termYear: values.termYear
            )
            if values.dueDate != course.dueDate {
                updated = try await client.setCourseDeadline(id: course.id, dueDate: values.dueDate)
            }
            if let index = courses.firstIndex(where: { $0.id == updated.id }) {
                courses[index] = updated
            }
        }
    }

    public func deleteCourse(_ course: Course) async {
        await run(verb: "delete") {
            try await client.deleteCourse(id: course.id)
            courses.removeAll { $0.id == course.id }
        }
    }

    /// Runs a mutation against `courses`, keeping every method's
    /// success/failure handling (clear the error, re-sort by name; on
    /// failure surface a message) in one shape instead of four copies
    /// (mirrors `WorkViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            courses.sort { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Course: \(error.localizedDescription)"
        }
    }
}
