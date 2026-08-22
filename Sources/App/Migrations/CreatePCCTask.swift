import Fluent

struct CreatePCCTask: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCTask.schema)
            .id()
            .field("title", .string, .required)
            .field("notes", .string)
            .field("is_complete", .bool, .required)
            // No `.required`: a Task is Project-less by default. `.setNull`
            // deletes the Project without cascading into its Tasks.
            .field("project_id", .uuid, .references(Project.schema, "id", onDelete: .setNull))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCTask.schema).delete()
    }
}
