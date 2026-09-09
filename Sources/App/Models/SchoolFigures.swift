import Foundation

/// The two academic figures — General Weighted Average and Units Earned
/// (`CONTEXT.md`) — as pure arithmetic over marks and unit counts, with no
/// request, database or `Course` model involved.
///
/// Split out from `SchoolReportingController` for the same reason `WorkTree`
/// and `SchoolBoard` are split out on the client side: these rules have
/// several edge cases that matter (a `5.00` counting one way but not the
/// other, `INC`/`DRP` counting neither way, an empty set having no average
/// at all) and each deserves a test that doesn't need a Postgres round trip
/// to state.
///
/// Takes `Contribution`s rather than `[Course]` so the per-Term and
/// cumulative scopes are the caller's filter, not a second parameter every
/// rule here would have to thread.
///
/// A pure `enum` namespace with no state, mirroring `SchoolBoard`.
enum SchoolFigures {
    /// One subject's contribution to a figure: the Grade it carries (`nil`
    /// while ongoing) and the Units it weighs.
    ///
    /// Not called a "Mark" — `CONTEXT.md`'s Grade entry puts that word on
    /// the avoid-list, and this is a Grade *plus* its weight rather than a
    /// grade by another name.
    struct Contribution {
        let grade: Grade?
        let units: Double
    }

    /// General Weighted Average: Σ(grade × units) ÷ Σ(units), over the marks
    /// that count toward it (`Grade.countsTowardGWA`) — every numeric mark,
    /// `5.00` included, and neither `INC` nor `DRP` nor an ungraded ongoing
    /// subject.
    ///
    /// `nil` when nothing counts yet. An average over no subjects is not
    /// zero — zero would read as a perfect score on a scale where low is
    /// good — so the absence travels as an absence and the tile says so.
    ///
    /// Unit-weighted over whatever marks it's handed, which is what makes
    /// the cumulative figure correct: the caller passes every subject across
    /// every Term rather than averaging the per-Term averages, since
    /// averaging averages overweights a light semester.
    static func generalWeightedAverage(over contributions: [Contribution]) -> Double? {
        // `countsTowardGWA` is defined as "has a numeric value", so reading
        // the number *is* the test — asking both would state the rule twice
        // and let the two copies drift.
        let counted = contributions.compactMap { contribution -> (value: Double, units: Double)? in
            guard let value = contribution.grade?.numericValue else { return nil }
            return (value, contribution.units)
        }
        let totalUnits = counted.reduce(0) { $0 + $1.units }
        guard totalUnits > 0 else { return nil }
        return counted.reduce(0) { $0 + $1.value * $1.units } / totalUnits
    }

    /// Units Earned: Σ(units) over passed subjects (`Grade.earnsUnits`).
    ///
    /// A failed subject earns nothing toward graduation even though its
    /// `5.00` still drags the average above — the two figures answer
    /// different questions, which is why they are two functions and not one
    /// pass over the same filter.
    ///
    /// Zero rather than `nil` when nothing has been passed: "no units earned
    /// yet" genuinely is zero units, unlike an average over nothing.
    static func unitsEarned(over contributions: [Contribution]) -> Double {
        contributions.reduce(0) { total, contribution in
            guard contribution.grade?.earnsUnits == true else { return total }
            return total + contribution.units
        }
    }
}
