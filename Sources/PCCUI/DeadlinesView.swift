import SwiftUI

/// Minimal Mac/iOS screen for ticket #5: the Deadline-proximity-sorted view
/// of every Task and Project together, with undated items still shown. One
/// shared SwiftUI view for both platforms — no platform-specific chrome, per
/// the ticket's "minimal" scope (mirrors `ProjectsView`/`TasksView`).
/// Read-only — set/clear a Deadline from the Tasks or Projects screen.
///
/// On the shared Liquid Glass system since issue #68 — full-width
/// `GlassBubble` rows on `GlassScreenBackground()`, replacing the earlier
/// countdown-clock costume (a dark-red alarm-panel palette) `git log` on
/// this file still shows. The countdown itself survives as a badge in
/// monospaced digits — see `CountdownBadge` below.
public struct DeadlinesView: View {
    @ObservedObject private var viewModel: DeadlinesViewModel

    public init(viewModel: DeadlinesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        DeadlinesContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `DeadlinesView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
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
                    itemScroll
                }
            }
            .background(GlassScreenBackground())
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

    /// A `ScrollView` of `DeadlineBubble`s rather than a `List` — this
    /// screen's whole point is liquid glass floating on plain white/black,
    /// which needs each row to draw its own translucent Material-backed
    /// shape (the shared `GlassBubble`) rather than a native list
    /// container's opaque row fill (mirrors `AccountsView`'s own move from
    /// `List` to `ScrollView` + custom cards for the same reason).
    private var itemScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                VStack(spacing: 14) {
                    ForEach(viewModel.items) { item in
                        DeadlineBubble(item: item)
                    }
                }
                .padding(.top, 18)
            }
            .padding(PCCChassis.outerMargin)
        }
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
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var overallStatus: PanelStatus {
        overdueCount > 0 ? .critical : .nominal
    }

    private var overdueCount: Int {
        viewModel.items.filter { DeadlinesViewModel.isOverdue($0) }.count
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
}

// MARK: - Deadline bubble

/// One Deadline row: the shared `GlassBubble` surface (`.fullWidth` size)
/// with this screen's own content on it — a kind glyph, the title/due date,
/// and a `CountdownBadge` as the loud hero figure. Set tighter than
/// `AccountBubble`/`TransactionBubble` (14pt vertical padding, not 20),
/// matching `TaskBubble`'s own density. The bubble's material, tint,
/// specular highlight and rim come from `PCCChassis`, not from here; only
/// the layout is this screen's.
private struct DeadlineBubble: View {
    let item: DeadlineItem

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Self.symbolName(for: item.kind))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .strikethrough(item.isComplete == true)
                if let dueDate = item.dueDate {
                    Text(dueDate, style: .date)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isOverdue ? theme.signalRed(colorScheme) : .secondary)
                } else {
                    Text("No date")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let countdown = DeadlinesViewModel.countdown(for: item) {
                CountdownBadge(countdown: countdown)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassBubble(Self.style)
    }

    private var isOverdue: Bool {
        DeadlinesViewModel.isOverdue(item)
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

// MARK: - Countdown badge

/// This screen's signature device, kept from the pre-glass version: a big
/// mono days-remaining readout, colored by urgency tier — the whole point
/// of this screen is "how much time is left," so that answer gets the
/// loudest number in the row, not the due date text next to it. Purely a
/// rendering of `DeadlineCountdown` (issue #68) — every bit of "what does
/// this say, what color is it" logic lives on `DeadlinesViewModel` now, so
/// this view just lays the two strings out and reads `PanelStatus.color`.
private struct CountdownBadge: View {
    let countdown: DeadlineCountdown

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(countdown.numberText)
                .font(.pccReadout(20))
                .foregroundStyle(color)
            Text(countdown.unitText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(color)
        }
        .frame(minWidth: 58, alignment: .trailing)
    }

    /// `.idle` (the "complete" tier) reads as plain `.secondary` rather
    /// than `PanelStatus`'s own dim chassis gray — this badge sits directly
    /// on a glass bubble, not a panel header, so it uses the same
    /// `.secondary` this screen already uses for its own "No date" label.
    private var color: Color {
        countdown.status == .idle ? .secondary : countdown.status.color(for: colorScheme, theme: theme)
    }
}
