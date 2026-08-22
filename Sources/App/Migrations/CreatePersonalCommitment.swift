import Fluent

struct CreatePersonalCommitment: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PersonalCommitment.schema)
            .id()
            .field("title", .string, .required)
            .field("start_date", .datetime, .required)
            .field("end_date", .datetime, .required)
            .field("recurrence_rule", .string)
            .field("external_event_id", .string, .required)
            .field("sync_status", .string, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PersonalCommitment.schema).delete()
    }
}
