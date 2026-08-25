import Fluent

/// Brand-new table, unlike `AddDeadlineToProject`/`AddClientToProject` —
/// `due_date` is part of the initial schema rather than a separate additive
/// migration, since there's no existing `courses` table to layer onto.
struct CreateCourse: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Course.schema)
            .id()
            .field("name", .string, .required)
            .field("term_month", .int, .required)
            .field("term_year", .int, .required)
            .field("due_date", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Course.schema).delete()
    }
}
