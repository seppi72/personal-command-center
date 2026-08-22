import Fluent
import Vapor

/// The atomic unit of work (`CONTEXT.md`). May belong to a Project — the
/// foreign key is optional and Project-less is a valid, ordinary state, not
/// an error case — and may carry a Deadline once that domain exists.
///
/// Named `PCCTask` in Swift only: an unqualified `Task` here would shadow
/// `_Concurrency.Task` for this whole target (and `PCCUI`, which already
/// relies on bare `Task { ... }` in `ProjectsView`). The domain term "Task"
/// is what shows up everywhere that matters — the `schema`, the JSON API,
/// docs, and UI text.
final class PCCTask: Model, @unchecked Sendable {
    static let schema = "tasks"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @OptionalField(key: "notes")
    var notes: String?

    @Field(key: "is_complete")
    var isComplete: Bool

    @OptionalParent(key: "project_id")
    var project: Project?

    init() {}

    init(id: UUID? = nil, title: String, notes: String? = nil, isComplete: Bool = false, projectID: UUID? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isComplete = isComplete
        self.$project.id = projectID
    }
}
