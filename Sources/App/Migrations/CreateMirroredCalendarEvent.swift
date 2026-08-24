import Fluent

struct CreateMirroredCalendarEvent: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(MirroredCalendarEvent.schema)
            .id()
            .field("external_event_id", .string, .required)
            .field("title", .string, .required)
            .field("start_date", .datetime, .required)
            .field("end_date", .datetime, .required)
            .field("last_synced_at", .datetime, .required)
            .unique(on: "external_event_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(MirroredCalendarEvent.schema).delete()
    }
}
