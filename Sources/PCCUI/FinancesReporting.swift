import Foundation

/// One day of a dense day-by-day series — mirrors the backend's own
/// `DailyFigure` (`Sources/App/Controllers/FinancesReportingController.swift`).
/// Shared by Net Worth trend and Account Balance history, the same "one
/// `{date, value}` shape covers both" reasoning the backend response type
/// already has.
public struct DailyFigure: Decodable, Identifiable, Sendable {
    public let date: Date
    public let value: Double

    public var id: Date { date }
}

/// One day of the expense-per-day series — mirrors the backend's own
/// `ExpensesPerDayRow`.
public struct ExpensesPerDayRow: Decodable, Identifiable, Sendable {
    public let date: Date
    public let totalExpenses: Double

    public var id: Date { date }
}

/// The two periods Projected Balance can extrapolate across (`CONTEXT.md`) —
/// mirrors the backend's own `ProjectedBalancePeriod`. `CaseIterable` so
/// `FinancesReportingView`'s `Picker` can enumerate both without listing them
/// a second time.
public enum ProjectedBalancePeriod: String, CaseIterable, Codable, Sendable {
    case week, month

    /// The label `FinancesReportingView`'s `Picker` shows for this case.
    public var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// Mirrors the backend's own `ProjectedBalanceResponse` — shown as a single
/// computed figure (text), not a chart (ticket #40's own settled scope).
public struct ProjectedBalance: Decodable, Sendable {
    public let averageDailyNet: Double
    public let projectedBalance: Double
    public let period: ProjectedBalancePeriod
}
