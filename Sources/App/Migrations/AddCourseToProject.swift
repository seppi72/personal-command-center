import Fluent

/// Ticket #88: attaches an optional Course to a Project — coursework that
/// has the Project shape, e.g. a semester group assignment
/// (`docs/adr/0011-project-belongs-to-client-xor-course.md`). An additive
/// migration on top of `CreateProject`/`AddClientToProject` rather than
/// editing either, since they may already have run against a real database.
///
/// No database-level CHECK enforcing the Client-xor-Course exclusivity:
/// Task's Project-xor-Course (ADR-0003) and Time Entry's four-way container
/// exclusivity (ADR-0004) are both enforced at write time in Swift
/// (`PCCTask.setContainer`, `TimeEntryController`), and ADR-0011 asks this
/// to follow whichever mechanism those already use rather than introduce a
/// third. `Project.setParent` is that write-time enforcement here.
///
/// `.cascade` rather than `.setNull`, matching
/// `AddCourseToPersonalCommitment`: this link is guarded —
/// `CourseController.delete` rejects deleting a Course while a Project still
/// belongs to it — so the cascade is a database-level fallback only, never
/// actually reached through the API.
struct AddCourseToProject: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Project.schema)
            .field("course_id", .uuid, .references(Course.schema, "id", onDelete: .cascade))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Project.schema)
            .deleteField("course_id")
            .update()
    }
}
