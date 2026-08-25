import Fluent
import Vapor

/// A container of related Tasks with its own lifecycle (`CONTEXT.md`). May
/// carry a Deadline (ticket #5) — modeled as a plain nullable field, same
/// tradeoff as `PCCTask.dueDate`. May optionally belong to a Client (ticket
/// #17) — the foreign key is optional and Client-less is a valid, ordinary
/// state, same shape as `PCCTask.project`.
final class Project: Model, @unchecked Sendable {
    static let schema = "projects"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "due_date")
    var dueDate: Date?

    @OptionalParent(key: "client_id")
    var client: PCCClient?

    init() {}

    init(id: UUID? = nil, name: String, dueDate: Date? = nil, clientID: UUID? = nil) {
        self.id = id
        self.name = name
        self.dueDate = dueDate
        self.$client.id = clientID
    }
}
