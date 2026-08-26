import Fluent
import Vapor

/// An owner-created label for grouping Transactions by kind of spending
/// (`CONTEXT.md`) — flat, with no field beyond a name; its Subcategories
/// (`Subcategory.category`) are the one level of nesting the domain allows.
///
/// Named `PCCCategory` in Swift only: an unqualified `Category` collides
/// with the Objective-C runtime's own `Category` typedef (`objc/runtime.h`,
/// pulled in transitively through Foundation on Darwin) — the same kind of
/// stdlib/runtime collision `PCCClient`/`PCCTask` already sidestep this way.
/// The domain term "Category" is what shows up everywhere that matters — the
/// `schema`, the JSON API (`categoryID`), docs, and UI text.
final class PCCCategory: Model, @unchecked Sendable {
    static let schema = "categories"

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
