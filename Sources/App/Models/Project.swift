import Fluent
import Vapor

/// A container of related Tasks with its own lifecycle (`CONTEXT.md`).
/// This slice (ticket #3) only tracks the name — Deadline and Client
/// references land in later tickets once those domains exist.
final class Project: Model, @unchecked Sendable {
    static let schema = "projects"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    init() {}

    init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}
