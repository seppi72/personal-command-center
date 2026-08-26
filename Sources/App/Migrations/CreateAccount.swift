import Fluent

struct CreateAccount: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Account.schema)
            .id()
            .field("name", .string, .required)
            .field("type", .string, .required)
            .field("opening_balance", .double, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Account.schema).delete()
    }
}
