import Fluent
import Vapor

/// A label one level under a Category (`CONTEXT.md`) — scoped to the
/// Category it was created in for its lifetime, the same "child pinned to
/// its parent" shape `Sprint.project` already has for Project. A Subcategory
/// doesn't itself have children — the domain's nesting stops here.
final class Subcategory: Model, @unchecked Sendable {
    static let schema = "subcategories"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Parent(key: "category_id")
    var category: PCCCategory

    init() {}

    init(id: UUID? = nil, name: String, categoryID: PCCCategory.IDValue) {
        self.id = id
        self.name = name
        self.$category.id = categoryID
    }
}
