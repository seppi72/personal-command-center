import Charts
import SwiftUI

/// Ticket #40: the Finances Reporting screen — Net Worth (current figure +
/// trend chart), one Account's Balance-over-time chart, an expense-per-day
/// chart across every Account, and one Account's Projected Balance shown as
/// a single computed figure (text), not a chart, per the ticket's own
/// settled scope. First use of SwiftUI's native `Charts` framework in
/// `PCCUI` — no third-party charting dependency, unlike every other screen's
/// plain-`List` convention (`WorkHoursView`'s own doc comment), since this
/// ticket's own AC calls for actual trend/history/expense charts rather than
/// rows of numbers.
public struct FinancesReportingView: View {
    @ObservedObject private var viewModel: FinancesReportingViewModel

    public init(viewModel: FinancesReportingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                rangeSection
                netWorthSection
                accountBalanceSection
                expensesSection
                projectedBalanceSection
            }
            .glassScreenBackground()
            .navigationTitle("Finances Reporting")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    /// One shared range for Net Worth trend, Account Balance history, and
    /// expense-per-day — reloads every affected section on change rather
    /// than needing a separate "Apply" step, the same immediate-reload
    /// convention `WorkHoursView`'s own `controls` uses.
    private var rangeSection: some View {
        Section("Range") {
            HStack {
                Text("Range")
                    .foregroundStyle(.secondary)
                Spacer()
                PCCDateRangeControl(selection: $viewModel.dateRange) {
                    Task { await reloadAll() }
                }
            }
        }
        .glassRows()
    }

    private var netWorthSection: some View {
        Section("Net Worth") {
            HStack {
                Text("Current")
                Spacer()
                Text(Self.currency(viewModel.currentNetWorth))
                    .foregroundStyle(.secondary)
            }
            if viewModel.netWorthTrend.isEmpty {
                emptyChartLabel
            } else {
                Chart(viewModel.netWorthTrend) { point in
                    LineMark(x: .value("Date", point.date, unit: .day), y: .value("Net Worth", point.value))
                        .foregroundStyle(Color.accentColor)
                    AreaMark(x: .value("Date", point.date, unit: .day), y: .value("Net Worth", point.value))
                        .foregroundStyle(Color.accentColor.opacity(0.15).gradient)
                }
                .frame(height: 160)
            }
        }
        .glassRows()
    }

    private var accountBalanceSection: some View {
        Section("Account Balance") {
            accountPicker
            if viewModel.accountBalanceHistory.isEmpty {
                emptyChartLabel
            } else {
                Chart(viewModel.accountBalanceHistory) { point in
                    LineMark(x: .value("Date", point.date, unit: .day), y: .value("Balance", point.value))
                        .foregroundStyle(Color.accentColor)
                    AreaMark(x: .value("Date", point.date, unit: .day), y: .value("Balance", point.value))
                        .foregroundStyle(Color.accentColor.opacity(0.15).gradient)
                }
                .frame(height: 160)
            }
        }
        .glassRows()
    }

    private var expensesSection: some View {
        Section("Expenses per Day") {
            if viewModel.expensesPerDay.isEmpty {
                emptyChartLabel
            } else {
                Chart(viewModel.expensesPerDay) { row in
                    BarMark(x: .value("Date", row.date, unit: .day), y: .value("Expenses", row.totalExpenses))
                        .foregroundStyle(Color.accentColor.gradient)
                }
                .frame(height: 160)
            }
        }
        .glassRows()
    }

    private var projectedBalanceSection: some View {
        Section("Projected Balance") {
            PCCMenuPicker(
                "Period",
                selection: $viewModel.projectedBalancePeriod,
                options: ProjectedBalancePeriod.allCases.map { ($0, $0.displayName) }
            )
            .onChange(of: viewModel.projectedBalancePeriod) { _ in
                Task { await viewModel.loadSelectedAccountFigures() }
            }
            if let projected = viewModel.projectedBalance {
                LabeledContent("Average Daily Net", value: Self.currency(projected.averageDailyNet))
                LabeledContent("Projected Balance", value: Self.currency(projected.projectedBalance))
            } else {
                Text("No Account selected").foregroundStyle(.secondary)
            }
        }
        .glassRows()
    }

    /// Shared by `accountBalanceSection` and, transitively,
    /// `projectedBalanceSection` — both read `viewModel.selectedAccountID`,
    /// so one picker drives both sections rather than each needing its own.
    private var accountPicker: some View {
        PCCMenuPicker(
            "Account",
            selection: $viewModel.selectedAccountID,
            options: viewModel.accounts.map { (Optional($0.id), $0.name) }
        )
        .onChange(of: viewModel.selectedAccountID) { _ in
            Task { await viewModel.loadSelectedAccountFigures() }
        }
    }

    private var emptyChartLabel: some View {
        Text("Nothing logged for this range yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func reloadAll() async {
        await viewModel.load()
    }

    private static func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: "PHP"))
    }
}
