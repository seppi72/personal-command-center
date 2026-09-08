import Fluent

/// Issue #120: Term as a new canonical entity, promoted out of Course's old
/// `term_month`/`term_year` pair (`docs/adr/0012-term-is-an-entity.md`).
///
/// Unique on `year` plus `semester` at the database level, not just in
/// `TermController`: this pair *is* the Term's identity, and a duplicate row
/// would split one semester's Courses across two Terms, quietly halving
/// every per-Term figure computed over them.
///
/// `start_date`/`end_date` are nullable — `AddTermToCourse` generates Terms
/// from existing Course data and cannot know the school's published calendar
/// spans, so it leaves them null rather than fabricating one.
struct CreateTerm: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Term.schema)
            .id()
            .field("year", .int, .required)
            .field("semester", .string, .required)
            .field("start_date", .datetime)
            .field("end_date", .datetime)
            .unique(on: "year", "semester")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Term.schema).delete()
    }
}
