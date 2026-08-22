import Fluent

/// Ticket #5: attaches a Deadline (`CONTEXT.md`) to a Project — an additive
/// migration on top of `CreateProject` rather than editing it, since that
/// migration may already have run against a real database.
struct AddDeadlineToProject: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Project.schema)
            .field("due_date", .datetime)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Project.schema)
            .deleteField("due_date")
            .update()
    }
}
