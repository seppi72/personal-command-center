import Fluent
import Vapor

/// A container of related Tasks with its own lifecycle (`CONTEXT.md`). May
/// carry a Deadline (ticket #5) — modeled as a plain nullable field, same
/// tradeoff as `PCCTask.dueDate`. Client references land in a later ticket
/// once that domain exists.
final class Project: Model, @unchecked Sendable {
    static let schema = "projects"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "due_date")
    var dueDate: Date?

    init() {}

    init(id: UUID? = nil, name: String, dueDate: Date? = nil) {
        self.id = id
        self.name = name
        self.dueDate = dueDate
    }
}
