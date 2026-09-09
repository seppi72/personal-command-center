import Foundation

/// Client-side mirror of the backend's `SchoolSummaryResponse` — the two
/// academic figures the School screen's tiles show (issue #92), computed
/// there rather than here so the arithmetic has one home and can't drift
/// from the grades underneath it (`Sources/App/Models/SchoolFigures.swift`).
///
/// This is the one figure family the School screen doesn't derive locally
/// through `SchoolBoard`: the rest are counts over lists it already holds,
/// while GWA is a rule with real edge cases (`5.00` counting toward the
/// average but not toward units, `INC`/`DRP` counting toward neither) that
/// would otherwise be written twice and kept agreeing by hand.
///
/// Both GWA figures are optional and mean "no marks that count yet". They
/// are deliberately not zero: zero would read as a *perfect* score on a
/// scale where low is good.
public struct SchoolSummary: Decodable, Equatable, Sendable {
    /// The Term `termGWA` describes, or `nil` when none was asked for.
    public let termID: UUID?
    /// That Term's General Weighted Average.
    public let termGWA: Double?
    /// Unit-weighted across every subject in every Term — not an average of
    /// the per-Term figures.
    public let cumulativeGWA: Double?
    /// Units over every passed subject, always cumulative.
    public let unitsEarned: Double

    public init(termID: UUID?, termGWA: Double?, cumulativeGWA: Double?, unitsEarned: Double) {
        self.termID = termID
        self.termGWA = termGWA
        self.cumulativeGWA = cumulativeGWA
        self.unitsEarned = unitsEarned
    }

    /// A GWA as the School screen prints it — two decimals, matching the
    /// scale the school itself publishes ("1.75"), or a dash when there is
    /// no figure yet.
    public static func formatted(_ gwa: Double?) -> String {
        guard let gwa else { return "—" }
        return String(format: "%.2f", gwa)
    }
}
