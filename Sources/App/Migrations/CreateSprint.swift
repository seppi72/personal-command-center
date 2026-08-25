import Fluent

struct CreateSprint: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Sprint.schema)
            .id()
            .field("name", .string, .required)
            .field("start_date", .datetime, .required)
            .field("end_date", .datetime, .required)
            // `.required`, unlike `AddClientToProject`'s `client_id`: a
            // Sprint always belongs to exactly one Project for its lifetime
            // (`Sprint.project` is a non-optional `@Parent`), so `.cascade`
            // deletes a Project's Sprints along with it rather than
            // `.setNull`-ing a foreign key that can't legally be null — a
            // different tradeoff from `AddClientToProject`'s `.setNull`,
            // where the child (Project) *can* exist without the parent.
            .field("project_id", .uuid, .required, .references(Project.schema, "id", onDelete: .cascade))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Sprint.schema).delete()
    }
}
