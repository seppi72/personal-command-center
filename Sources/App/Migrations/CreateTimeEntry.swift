import Fluent

/// Ticket #27: Time Entry as a new canonical entity — a record spanning a
/// start and end time, attached to exactly one of Task, Project, Client, or
/// Course (`docs/adr/0004-time-entry-container-includes-course.md`).
struct CreateTimeEntry: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(TimeEntry.schema)
            .id()
            .field("start_date", .datetime, .required)
            .field("end_date", .datetime, .required)
            .field("notes", .string)
            // Exactly one of these four is ever non-nil for a given row
            // (`TimeEntryController` enforces it at write time) — none is
            // `.required` since none is unconditionally set, but each is
            // `.cascade` rather than `.setNull`: unlike e.g. `PCCTask`'s
            // `project_id`, a Time Entry can't legally exist
            // container-less, so deleting the referenced Task/Project/
            // Client/Course must delete the Time Entry along with it
            // instead of leaving a row with all four foreign keys nil.
            .field("task_id", .uuid, .references(PCCTask.schema, "id", onDelete: .cascade))
            .field("project_id", .uuid, .references(Project.schema, "id", onDelete: .cascade))
            .field("client_id", .uuid, .references(PCCClient.schema, "id", onDelete: .cascade))
            .field("course_id", .uuid, .references(Course.schema, "id", onDelete: .cascade))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TimeEntry.schema).delete()
    }
}
