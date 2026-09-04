import Fluent

/// Ticket #88: attaches an optional Kind to a Task — a label naming what
/// sort of work it is, e.g. homework, study, reading (`CONTEXT.md`). An
/// additive migration on top of `CreatePCCTask`, mirroring
/// `AddCompletedAtToPCCTask`'s shape.
///
/// A free-text `.string` rather than an enum column: Kind is display and
/// filtering only — it carries no behaviour and doesn't affect containment —
/// and `CONTEXT.md` describes it open-endedly ("homework, study, reading,
/// and the like"), so a closed set would have to be migrated every time the
/// owner wants a new label for no gain.
struct AddKindToPCCTask: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .field("kind", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .deleteField("kind")
            .update()
    }
}
