import Fluent

/// Ticket #37: Transaction as a new canonical entity — a signed movement of
/// money against exactly one Account (`CONTEXT.md`).
struct CreateTransaction: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Transaction.schema)
            .id()
            .field("amount", .double, .required)
            .field("type", .string, .required)
            .field("date", .datetime, .required)
            .field("notes", .string)
            // Required, non-optional — a Transaction can't exist
            // accountless any more than a Time Entry can exist
            // container-less (`CONTEXT.md`'s Transaction entry). `.cascade`
            // matches `CreateTimeEntry`'s own FKs (Transaction model's doc
            // comment).
            .field("account_id", .uuid, .required, .references(Account.schema, "id", onDelete: .cascade))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Transaction.schema).delete()
    }
}
