import Fluent

/// Dashboard "on-time completion rate" widget: records when a Task was last
/// marked complete, so `TaskController.setCompletion` can stamp it and the
/// client can compare it against `dueDate`. An additive migration on top of
/// `CreatePCCTask`, mirroring `AddDeadlineToPCCTask`'s shape, rather than
/// editing that migration — it may already have run against a real
/// database. Only accurate for Tasks completed after this migration runs;
/// nothing backfills a `completedAt` for Tasks already marked complete.
struct AddCompletedAtToPCCTask: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .field("completed_at", .datetime)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .deleteField("completed_at")
            .update()
    }
}
