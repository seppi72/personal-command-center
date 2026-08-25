import Fluent

/// Ticket #18: attaches a Sprint (`CONTEXT.md`) to a Task — an additive
/// migration on top of `CreatePCCTask` rather than editing it, since that
/// migration may already have run against a real database (same reasoning
/// as `AddClientToProject`).
struct AddSprintToPCCTask: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            // No `.required`: a Task can be Sprint-less, whether because it
            // was never assigned one or because its Sprint was deleted.
            // `.setNull` orphans the Task rather than deleting it when its
            // Sprint is deleted (ticket #18's AC) — the same shape
            // `CreatePCCTask`'s own `project_id` already has for a deleted
            // Project.
            .field("sprint_id", .uuid, .references(Sprint.schema, "id", onDelete: .setNull))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .deleteField("sprint_id")
            .update()
    }
}
