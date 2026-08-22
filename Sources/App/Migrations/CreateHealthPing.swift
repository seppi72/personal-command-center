import Fluent

struct CreateHealthPing: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(HealthPing.schema)
            .id()
            .field("count", .int, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(HealthPing.schema).delete()
    }
}
