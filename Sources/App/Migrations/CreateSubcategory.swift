import Fluent

/// Ticket #39: Subcategory as a new canonical entity, scoped to exactly one
/// parent Category for its lifetime (`CONTEXT.md`) — `.required`, the same
/// "non-reassignable child" shape `CreateSprint`'s own `project_id` already
/// has for Project. `.cascade` deletes a Category's Subcategories along with
/// it, matching `CreateSprint`'s reasoning: `Subcategory.category` is a
/// non-optional `@Parent`, so there's no legal null state to `.setNull` into.
struct CreateSubcategory: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Subcategory.schema)
            .id()
            .field("name", .string, .required)
            .field("category_id", .uuid, .required, .references(PCCCategory.schema, "id", onDelete: .cascade))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Subcategory.schema).delete()
    }
}
