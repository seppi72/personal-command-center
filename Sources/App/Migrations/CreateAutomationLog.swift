import Fluent

struct CreateAutomationLog: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(AutomationLog.schema)
            .id()
            .field("action_type", .string, .required)
            .field("subject_type", .string, .required)
            .field("subject_id", .uuid, .required)
            .field("detail", .string, .required)
            .field("outcome", .string, .required)
            .field("occurred_at", .datetime, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(AutomationLog.schema).delete()
    }
}
