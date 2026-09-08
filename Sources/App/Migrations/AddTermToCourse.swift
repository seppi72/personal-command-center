import Fluent
import Foundation
import PostgresKit

/// Issue #120: replaces Course's `term_month`/`term_year` pair with a
/// required reference to a real `Term` row
/// (`docs/adr/0012-term-is-an-entity.md`).
///
/// Runs in four steps rather than one schema edit, because the column can
/// only be `.required` once every existing Course already points at a Term:
///
/// 1. add `term_id`, nullable for now;
/// 2. create one Term per distinct `term_month`/`term_year` pair already in
///    the data, and point that pair's Courses at it;
/// 3. tighten `term_id` to `NOT NULL`;
/// 4. drop `term_month`/`term_year`.
///
/// The generated Terms get a **guessed** semester (see `semester(forMonth:)`)
/// and keep `start_date`/`end_date` null. A made-up calendar span would
/// silently mislabel which Term is current; null reads honestly as "not set
/// yet", and a Term with no dates is never auto-selected as the current one.
///
/// Distinct month/year pairs can collapse onto the same year-and-semester
/// (August and October 2026 are both 1st Semester 2026), so the backfill
/// reuses the Term it already created for a pair rather than inserting a
/// duplicate `CreateTerm`'s unique index would reject anyway.
///
/// `.restrict` rather than the `.cascade` `AddCourseToProject` chose:
/// `Course.term` is a non-optional `@Parent`, so there's no null to
/// `.setNull` into, and cascading would delete a whole semester of academic
/// history along with the Term. `TermController.delete` blocks the delete
/// with a readable error before the database ever has to; `.restrict` is the
/// truthful database-level fallback behind it.
///
/// Fluent's schema builder has no "tighten an existing column to NOT NULL"
/// operation, so step 3 runs the `ALTER TABLE` directly through
/// `SQLDatabase`, the same escape hatch `MakeTimeEntryEndDateOptional` uses.
struct AddTermToCourse: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Course.schema)
            .field("term_id", .uuid, .references(Term.schema, "id", onDelete: .restrict))
            .update()

        try await backfillTerms(on: database)

        try await sql(database)
            .raw("ALTER TABLE \(unsafeRaw: Course.schema) ALTER COLUMN term_id SET NOT NULL")
            .run()

        try await database.schema(Course.schema)
            .deleteField("term_month")
            .deleteField("term_year")
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Course.schema)
            .field("term_month", .int)
            .field("term_year", .int)
            .update()

        try await restoreMonthAndYear(on: database)

        try await sql(database)
            .raw("ALTER TABLE \(unsafeRaw: Course.schema) ALTER COLUMN term_month SET NOT NULL")
            .run()
        try await sql(database)
            .raw("ALTER TABLE \(unsafeRaw: Course.schema) ALTER COLUMN term_year SET NOT NULL")
            .run()

        try await database.schema(Course.schema)
            .deleteField("term_id")
            .update()
    }

    // MARK: - Backfill

    private func backfillTerms(on database: any Database) async throws {
        let rows = try await sql(database)
            .raw("SELECT DISTINCT term_month, term_year FROM \(unsafeRaw: Course.schema)")
            .all()

        var termIDsByYearAndSemester: [String: UUID] = [:]
        for row in rows {
            let month = try row.decode(column: "term_month", as: Int.self)
            let year = try row.decode(column: "term_year", as: Int.self)
            let semester = Self.semester(forMonth: month)

            let key = "\(year)-\(semester.rawValue)"
            let termID: UUID
            if let existing = termIDsByYearAndSemester[key] {
                termID = existing
            } else {
                let term = Term(year: year, semester: semester)
                try await term.save(on: database)
                termID = try term.requireID()
                termIDsByYearAndSemester[key] = termID
            }

            try await sql(database)
                .raw(
                    """
                    UPDATE \(unsafeRaw: Course.schema) SET term_id = \(bind: termID)
                    WHERE term_month = \(bind: month) AND term_year = \(bind: year)
                    """
                )
                .run()
        }
    }

    /// The semester a pre-migration Course's month most likely belonged to,
    /// following the owner's school calendar: 1st Semester runs August
    /// through December, 2nd Semester January through May, and Summer fills
    /// the June-July gap between them. A guess, not a fact — the old data
    /// recorded only a month, and the school's real calendar was never
    /// stored.
    static func semester(forMonth month: Int) -> Semester {
        switch month {
        case 8...12: return .first
        case 6...7: return .summer
        default: return .second
        }
    }

    /// The inverse guess, for `revert`: the month a semester starts in.
    /// Reverting can't recover the original month a Course carried — several
    /// months map onto one semester — so it restores the semester's first
    /// month rather than pretending to know which one it was.
    private func restoreMonthAndYear(on database: any Database) async throws {
        for semester in Semester.allCases {
            try await sql(database)
                .raw(
                    """
                    UPDATE \(unsafeRaw: Course.schema) AS c
                    SET term_month = \(bind: Self.firstMonth(of: semester)), term_year = t.year
                    FROM \(unsafeRaw: Term.schema) AS t
                    WHERE c.term_id = t.id AND t.semester = \(bind: semester.rawValue)
                    """
                )
                .run()
        }
    }

    private static func firstMonth(of semester: Semester) -> Int {
        switch semester {
        case .first: return 8
        case .second: return 1
        case .summer: return 6
        }
    }

    private func sql(_ database: any Database) -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            fatalError("AddTermToCourse requires a SQLDatabase-backed database")
        }
        return sql
    }
}
