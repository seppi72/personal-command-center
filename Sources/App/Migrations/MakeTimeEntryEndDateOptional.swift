import Fluent
import PostgresKit

/// Ticket #28: a live timer is modeled as a `TimeEntry` row that hasn't
/// been stopped yet — `endDate == nil` (`TimeEntry.isRunning`) — rather than
/// a separate table, so stopping a timer is just setting the same
/// `end_date` column `TimeEntryController` already validates around for
/// manual entries. `end_date` was `.required` since `CreateTimeEntry`;
/// Fluent's schema builder has no "drop NOT NULL on an existing column"
/// operation, so this runs the `ALTER TABLE` directly through
/// `SQLDatabase`, which `FluentPostgresDriver`'s database conforms to.
struct MakeTimeEntryEndDateOptional: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await sql(database).raw("ALTER TABLE \(unsafeRaw: TimeEntry.schema) ALTER COLUMN end_date DROP NOT NULL").run()
    }

    /// Reverting requires every row to already have a non-nil `end_date` —
    /// this would fail against a database with a running timer at the time,
    /// same as any migration revert that tightens a constraint the data no
    /// longer satisfies.
    func revert(on database: any Database) async throws {
        try await sql(database).raw("ALTER TABLE \(unsafeRaw: TimeEntry.schema) ALTER COLUMN end_date SET NOT NULL").run()
    }

    private func sql(_ database: any Database) -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            fatalError("MakeTimeEntryEndDateOptional requires a SQLDatabase-backed database")
        }
        return sql
    }
}
