import Fluent

/// Ticket #56: attaches an optional Course to a Personal Commitment — a
/// class meeting time logged as a Commitment (`CONTEXT.md`,
/// `docs/adr/0009-manual-entry-not-lms-integration-for-school.md`). An
/// additive migration on top of `CreatePersonalCommitment`, following the
/// same "don't edit an already-run migration" precedent as
/// `AddCourseToPCCTask`/`AddSprintToPCCTask`.
///
/// `.cascade` rather than `.setNull`: unlike `PCCTask`'s unguarded
/// `course_id`, this link is guarded — `CourseController.delete` rejects
/// deleting a Course while a Personal Commitment still references it
/// (mirroring the same guard already in place for Time Entry's containers
/// and Finances' Accounts), so this cascade is a database-level fallback
/// only, never actually reached through the API.
struct AddCourseToPersonalCommitment: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PersonalCommitment.schema)
            .field("course_id", .uuid, .references(Course.schema, "id", onDelete: .cascade))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PersonalCommitment.schema)
            .deleteField("course_id")
            .update()
    }
}
