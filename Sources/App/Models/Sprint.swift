import Fluent
import Vapor

/// A time-boxed iteration within one Project that Tasks can be grouped into
/// (`CONTEXT.md`). A Project's use of Sprints is optional, but a Sprint
/// itself is scoped to the Project it was created in for its lifetime — it
/// doesn't move to a different Project, so unlike `PCCTask.project` (an
/// `@OptionalParent`), `Sprint.project` is a non-optional `@Parent`: a
/// Sprint cannot exist without exactly one owning Project.
final class Sprint: Model, @unchecked Sendable {
    static let schema = "sprints"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "start_date")
    var startDate: Date

    @Field(key: "end_date")
    var endDate: Date

    @Parent(key: "project_id")
    var project: Project

    init() {}

    init(id: UUID? = nil, name: String, startDate: Date, endDate: Date, projectID: Project.IDValue) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.$project.id = projectID
    }
}
