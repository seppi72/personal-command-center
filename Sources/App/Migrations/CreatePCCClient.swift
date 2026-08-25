import Fluent

struct CreatePCCClient: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCClient.schema)
            .id()
            .field("name", .string, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCClient.schema).delete()
    }
}
