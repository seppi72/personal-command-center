import Fluent

/// Ticket #17: attaches a Client (`CONTEXT.md`) to a Project — an additive
/// migration on top of `CreateProject` rather than editing it, since that
/// migration may already have run against a real database.
struct AddClientToProject: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Project.schema)
            // No `.required`: a Project is Client-less by default. `.setNull`
            // orphans the Project rather than deleting it when its Client is
            // deleted (ticket #17's AC).
            .field("client_id", .uuid, .references(PCCClient.schema, "id", onDelete: .setNull))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Project.schema)
            .deleteField("client_id")
            .update()
    }
}
