import Fluent

/// Ticket #39: Category as a new canonical entity — an owner-created label
/// for grouping Transactions by kind of spending (`CONTEXT.md`), flat like
/// `CreatePCCClient`/`CreateAccount` (no field beyond a name).
struct CreateCategory: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PCCCategory.schema)
            .id()
            .field("name", .string, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PCCCategory.schema).delete()
    }
}
