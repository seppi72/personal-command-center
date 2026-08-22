import Fluent

/// Ticket #5: attaches a Deadline (`CONTEXT.md`) to a Task — an additive
/// migration on top of `CreatePCCTask` rather than editing it, since that
/// migration may already have run against a real database.
struct AddDeadlineToPCCTask: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .field("due_date", .datetime)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .deleteField("due_date")
            .update()
    }
}
