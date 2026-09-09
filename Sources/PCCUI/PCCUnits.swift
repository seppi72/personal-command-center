import Foundation

/// How a Units figure is written wherever this app shows one (`CONTEXT.md`)
/// — a Course's own weight on its card and in its form, and the Units Earned
/// total on the School screen.
///
/// A namespace of its own rather than a method on `Course` or on
/// `SchoolSummary`: the three call sites hold three different things (a
/// Course, an editable form value, a cumulative total), and hanging the
/// spelling off any one of them would make the other two reach into a type
/// they otherwise have no business with. Mirrors `PCCDuration`, which is the
/// same move for hours.
public enum PCCUnits {
    /// Whole counts print bare ("21"), halves to one decimal ("21.5"), since
    /// a Course may carry either and a trailing ".0" reads as precision the
    /// figure doesn't have.
    public static func text(_ units: Double) -> String {
        units == units.rounded()
            ? String(format: "%.0f", units)
            : String(format: "%.1f", units)
    }
}
