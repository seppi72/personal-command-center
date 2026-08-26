import Fluent

struct CreateNotification: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCNotification.schema)
            .id()
            .field("source_type", .string, .required)
            .field("source_id", .uuid, .required)
            .field("message", .string, .required)
            .field("is_dismissed", .bool, .required)
            .field("created_at", .datetime, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCNotification.schema).delete()
    }
}
