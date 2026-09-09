import Fluent
import PostgresKit

/// Issue #92: a Course carries its `units` and its final `grade`
/// (`CONTEXT.md`), the two fields General Weighted Average and Units Earned
/// are computed from.
///
/// `grade` is plainly nullable — an ongoing subject has no mark yet, so null
/// is a real value here rather than missing data.
///
/// `units` is required, and required columns can't simply be added to a
/// table that already has rows. It goes on in three steps, the same shape
/// `AddTermToCourse` uses for its own tightening:
///
/// 1. add `units`, nullable for now;
/// 2. fill every existing Course with `defaultUnits`;
/// 3. tighten the column to `NOT NULL`.
///
/// Step 2 is a **guess**, and the only honest one available: the old schema
/// recorded no unit count anywhere, and a Course with `0` units would
/// contribute nothing to either figure while looking like real data — worse
/// than a wrong number the owner can see and correct on the Course card.
/// Three units is the ordinary subject at this school, so that is what a
/// pre-existing Course gets until it's edited.
///
/// Fluent's schema builder has no "tighten an existing column to NOT NULL"
/// operation, so step 3 runs the `ALTER TABLE` through `SQLDatabase`
/// directly, the same escape hatch `AddTermToCourse` and
/// `MakeTimeEntryEndDateOptional` already use.
struct AddGradeAndUnitsToCourse: AsyncMigration {
    /// What a Course created before this migration is assumed to be worth.
    /// See the note above on why this is a visible guess rather than zero.
    static let defaultUnits = 3.0

    func prepare(on database: any Database) async throws {
        try await database.schema(Course.schema)
            .field("units", .double)
            .field("grade", .string)
            .update()

        try await sql(database)
            .raw("UPDATE \(unsafeRaw: Course.schema) SET units = \(bind: Self.defaultUnits) WHERE units IS NULL")
            .run()

        try await sql(database)
            .raw("ALTER TABLE \(unsafeRaw: Course.schema) ALTER COLUMN units SET NOT NULL")
            .run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Course.schema)
            .deleteField("units")
            .deleteField("grade")
            .update()
    }

    private func sql(_ database: any Database) -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            fatalError("AddGradeAndUnitsToCourse requires a SQLDatabase-backed database")
        }
        return sql
    }
}
