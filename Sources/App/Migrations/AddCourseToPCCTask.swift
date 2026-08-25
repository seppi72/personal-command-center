import Fluent

/// Ticket #20: attaches a Course (`CONTEXT.md`) to a Task — an additive
/// migration on top of `CreatePCCTask`/`AddSprintToPCCTask` rather than
/// editing either, since they may already have run against a real database
/// (same reasoning as `AddSprintToPCCTask`).
struct AddCourseToPCCTask: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            // No `.required`: a Task is Course-less by default, and per
            // ADR-0003 a Task belongs to at most one of {Project, Course} —
            // `courseID` and `projectID` are never both set.  `.setNull`
            // orphans the Task rather than deleting it when its Course is
            // deleted, the same shape `course_id`'s sibling FKs already have.
            .field("course_id", .uuid, .references(Course.schema, "id", onDelete: .setNull))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .deleteField("course_id")
            .update()
    }
}
