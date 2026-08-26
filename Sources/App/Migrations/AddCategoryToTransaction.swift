import Fluent

/// Ticket #39: attaches an optional Category and/or Subcategory
/// (`CONTEXT.md`) to a Transaction — an additive migration on top of
/// `CreateTransaction` rather than editing it, since that migration may
/// already have run against a real database (same reasoning as
/// `AddClientToProject`/`AddSprintToPCCTask`).
///
/// Both foreign keys use `.setNull`, not `.cascade`: a Transaction's Category
/// is optional where its Account is required (`CreateTransaction`'s own
/// `account_id`), so deleting a Category or Subcategory orphans any
/// referencing Transaction rather than deleting it along with it — the
/// opposite tradeoff from ticket #38's Account/Transaction guard, made
/// explicit in this ticket's AC. Deleting a Category cascade-deletes its
/// Subcategories (`CreateSubcategory`'s own `.cascade`), and still nulls out
/// any Transaction's `subcategory_id` that pointed at one of them: Postgres
/// re-evaluates each cascaded Subcategory delete's own `.setNull` FK in turn,
/// so no extra application code is needed to reach that state.
struct AddCategoryToTransaction: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Transaction.schema)
            .field("category_id", .uuid, .references(PCCCategory.schema, "id", onDelete: .setNull))
            .field("subcategory_id", .uuid, .references(Subcategory.schema, "id", onDelete: .setNull))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Transaction.schema)
            .deleteField("category_id")
            .deleteField("subcategory_id")
            .update()
    }
}
