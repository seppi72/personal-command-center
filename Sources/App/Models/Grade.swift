import Vapor

/// The final mark a Course carries (`CONTEXT.md`) — entered by the owner,
/// never computed from individual assignment scores
/// (`docs/adr/0013-owner-entered-course-grade-over-computed-gradebook.md`).
///
/// A closed ladder rather than free numeric entry, the same fixed,
/// non-owner-configurable shape `AccountType` and `Semester` already have:
/// the school issues one of these values and nothing between them, so a
/// picker is the entry control and anything else is a bad request.
///
/// **Lower is better.** `1.00` is the highest mark on this scale, `3.00` is
/// the passing mark, and `5.00` is failure — no other figure in this app
/// runs that direction, so every consumer has to invert deliberately rather
/// than inherit the usual "up is good" treatment.
///
/// Two non-numeric marks share the field, which is why this is an enum
/// rather than a validated `Double`:
///
/// - `drp` (dropped) is terminal — the subject is over and counts toward
///   nothing.
/// - `inc` (incomplete) is not terminal — the subject still reads as
///   ongoing until the mark is replaced with a real one.
///
/// Raw values are the marks exactly as the school prints them ("1.25",
/// "INC"), deliberately breaking this API's camelCase JSON convention (e.g.
/// `AccountType.creditCard`): these strings are the domain's own spelling,
/// they are what the owner reads off a transcript, and inventing
/// `oneTwentyFive` for the wire would make every payload harder to check
/// against the document it was copied from.
enum Grade: String, Codable, CaseIterable, Sendable {
    case one = "1.00"
    case oneTwentyFive = "1.25"
    case oneFifty = "1.50"
    case oneSeventyFive = "1.75"
    case two = "2.00"
    case twoTwentyFive = "2.25"
    case twoFifty = "2.50"
    case twoSeventyFive = "2.75"
    case three = "3.00"
    case five = "5.00"
    case incomplete = "INC"
    case dropped = "DRP"

    /// The mark's value on the numeric scale, or `nil` for `inc`/`drp`,
    /// which have none. This `nil` is the single fact both figures branch on
    /// — a mark with no number can weigh nothing in an average.
    var numericValue: Double? {
        Double(rawValue)
    }

    /// The passing mark. Anything numerically above it fails; `inc`/`drp`
    /// are neither, having no number at all.
    static let passingMark = 3.00

    /// Whether this mark contributes to General Weighted Average. Every
    /// numeric mark does, `5.00` included — a failure is a real grade and
    /// should drag the average down.
    var countsTowardGWA: Bool {
        numericValue != nil
    }

    /// Whether this mark earns its Course's units toward graduation. Only a
    /// passing numeric mark does: a `5.00` counts toward the average but
    /// earns nothing, which is why this is a separate question from
    /// `countsTowardGWA` rather than the same one asked twice.
    var earnsUnits: Bool {
        guard let numericValue else { return false }
        return numericValue <= Self.passingMark
    }

    /// Whether the subject still reads as ongoing despite carrying a mark.
    /// Only `inc` does — an incomplete is a placeholder for a grade the
    /// school hasn't finished issuing, unlike `drp`, which ends the subject.
    var isOngoing: Bool {
        self == .incomplete
    }
}
