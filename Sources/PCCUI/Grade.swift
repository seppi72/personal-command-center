import Foundation

/// Client-side mirror of the backend's `Grade` — the final mark a Course
/// carries (`CONTEXT.md`), entered by the owner rather than computed from
/// assignment scores
/// (`docs/adr/0013-owner-entered-course-grade-over-computed-gradebook.md`).
///
/// A closed ladder, so the entry control is a picker rather than a numeric
/// field: the school issues one of these values and nothing between them.
/// `CaseIterable` in declaration order is what that picker lists — best mark
/// first, then the failure, then the two non-numeric marks.
///
/// **Lower is better**, which no other figure in this app does. Anything
/// this enum feeds — a colour, an arrow, a bar — has to invert deliberately.
public enum Grade: String, Codable, CaseIterable, Identifiable, Sendable {
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

    public var id: String { rawValue }

    /// The passing mark on this scale. Anything numerically above it fails —
    /// mirrors the backend's own `Grade.passingMark`, which is what both
    /// figures are computed against.
    public static let passingMark = 3.00

    /// The mark as the school prints it — the raw value is already that
    /// spelling, so a picker row shows the same string the transcript does.
    public var displayName: String { rawValue }

    /// How the mark reads on a Course card. An `INC` says so: the mark is
    /// recorded, but the subject is *not* over (`isOngoing`) and counts
    /// toward neither figure until the school replaces it, which a bare
    /// "INC" beside a finished subject's "1.75" would not convey.
    public var cardLabel: String {
        isOngoing ? "\(rawValue) · ONGOING" : rawValue
    }

    /// How the mark reads in the Course form's picker. The three marks whose
    /// meaning isn't self-evident from the number say what they are, since
    /// the ladder runs the opposite way to every other figure in this app
    /// and a picker of bare decimals gives no clue which end is good.
    public var pickerTitle: String {
        switch self {
        case .one: return "1.00 — highest"
        case .three: return "3.00 — passing"
        case .five: return "5.00 — failed"
        case .incomplete: return "INC — incomplete"
        case .dropped: return "DRP — dropped"
        default: return rawValue
        }
    }

    /// The mark's value on the numeric scale, or `nil` for `inc`/`drp`.
    public var numericValue: Double? { Double(rawValue) }

    /// Whether the subject still reads as ongoing despite carrying a mark —
    /// only `inc` does, which is why an incomplete Course is shown as in
    /// progress rather than finished.
    public var isOngoing: Bool { self == .incomplete }
}
