import SwiftUI

/// Minimal Mac/iOS screen for ticket #5: the Deadline-proximity-sorted view
/// of every Task and Project together, with undated items still shown. One
/// shared SwiftUI view for both platforms — no platform-specific chrome, per
/// the ticket's "minimal" scope (mirrors `ProjectsView`/`TasksView`).
/// Read-only — set/clear a Deadline from the Tasks or Projects screen.
public struct DeadlinesView: View {
    @ObservedObject private var viewModel: DeadlinesViewModel

    public init(viewModel: DeadlinesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        DeadlinesContent(viewModel: viewModel)
            .screenTheme(.countdownClock)
    }
}

/// The screen's actual content — split out from `DeadlinesView` itself so
/// `.screenTheme(.countdownClock)` (applied in that struct's body, above)
/// is genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct DeadlinesContent: View {
    @ObservedObject var viewModel: DeadlinesViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    itemList
                }
            }
            .background(PanelBackground())
            .navigationTitle("Deadlines")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Error", isPresented: isShowingError, presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private var itemList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.items) { item in
                    HStack {
                        Image(systemName: Self.symbolName(for: item.kind))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .strikethrough(item.isComplete == true)
                            if let dueDate = item.dueDate {
                                Text(dueDate, style: .date)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Self.isOverdue(item) ? theme.signalRed(colorScheme) : .secondary)
                            } else {
                                Text("No date")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let dueDate = item.dueDate {
                            CountdownBadge(dueDate: dueDate, isComplete: item.isComplete == true)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .panelRows()
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(overallStatus)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var overallStatus: PanelStatus {
        overdueCount > 0 ? .critical : .nominal
    }

    private var overdueCount: Int {
        viewModel.items.filter(Self.isOverdue).count
    }

    private static func isOverdue(_ item: DeadlineItem) -> Bool {
        guard let dueDate = item.dueDate, item.isComplete != true else { return false }
        return dueDate < Date()
    }

    private var statusStripText: String {
        let count = viewModel.items.count
        let noun = count == 1 ? "DEADLINE" : "DEADLINES"
        let flagText = overdueCount > 0 ? "\(overdueCount) OVERDUE" : "ALL CLEAR"
        return "\(count) \(noun)   ·   \(flagText)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Deadlines")
                .font(.headline)
            Text("Attach a due date to a Task or Project to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { viewModel.errorMessage = nil } }
        )
    }

    /// Each `DeadlineItem.Kind`'s row glyph — a Course reuses neither the
    /// Task nor the Project glyph, since it's a third, distinct kind of
    /// container (ticket #20).
    private static func symbolName(for kind: DeadlineItem.Kind) -> String {
        switch kind {
        case .task: return "checkmark.circle"
        case .project: return "folder"
        case .course: return "graduationcap"
        }
    }
}

// MARK: - Countdown Clock theme

extension ScreenTheme {
    /// `DeadlinesView`'s own vibe: an alarm-clock countdown console. No
    /// separate neutral accent hue — every number on this screen is
    /// itself an urgency signal, so `accent` is just set to the same LED
    /// red `signalRed` already uses, rather than introducing a fourth hue
    /// with no distinct job to do. Signal green/amber/red are left as
    /// `ScreenTheme.default`'s — this screen's whole point is reading
    /// those tiers correctly, no reason to shift them.
    fileprivate static let countdownClock = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x180A0A) : Color(hex: 0xFAF4F2) },
        panelSurface: { $0 == .dark ? Color(hex: 0x241210) : Color(hex: 0xFFFFFF) },
        panelLine: { $0 == .dark ? Color(hex: 0x4A2420) : Color(hex: 0xECD9D4) },
        accent: ScreenTheme.default.signalRed,
        signalGreen: ScreenTheme.default.signalGreen,
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: ScreenTheme.default.signalRed
    )
}

// MARK: - Countdown badge

/// This screen's signature device: a big mono days-remaining readout,
/// colored by urgency tier — the whole point of this screen is "how much
/// time is left," so that answer gets the loudest number in the row,
/// not the due date text next to it.
private struct CountdownBadge: View {
    let dueDate: Date
    let isComplete: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    /// Calendar-day difference between today and `dueDate`, not a raw
    /// time-interval division — comparing by calendar day avoids an
    /// off-by-one read near midnight that a `/ 86400` would risk.
    private var daysRemaining: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfDue = calendar.startOfDay(for: dueDate)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfDue).day ?? 0
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(numberText)
                .font(.pccReadout(20))
                .foregroundStyle(color)
            Text(unitText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(color)
        }
        .frame(minWidth: 58, alignment: .trailing)
    }

    private var numberText: String {
        "\(abs(daysRemaining))D"
    }

    private var unitText: String {
        if isComplete { return "Done" }
        if daysRemaining < 0 { return "Overdue" }
        if daysRemaining == 0 { return "Today" }
        return "Left"
    }

    /// Green past the 3-day mark, amber inside it (including "today"),
    /// red once overdue — the same three-tier urgency vocabulary
    /// `PanelStatus` uses elsewhere in the chassis, applied directly to
    /// this screen's own hero number instead of a header lamp.
    private var color: Color {
        if isComplete { return .secondary }
        if daysRemaining < 0 { return theme.signalRed(colorScheme) }
        if daysRemaining <= 3 { return theme.signalAmber(colorScheme) }
        return theme.signalGreen(colorScheme)
    }
}
