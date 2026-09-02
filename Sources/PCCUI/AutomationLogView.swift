import SwiftUI

/// Minimal Mac/iOS screen for ticket #8: recent `AutomationLog` entries
/// (`CONTEXT.md`) — what the system has done on its own, e.g. a CalDAV push
/// or Calendar pull — with the most recent sync failure, if any, surfaced as
/// a banner up top rather than left to be spotted by scrolling (this
/// ticket's "surfaced clearly... rather than failing silently" AC). One
/// shared SwiftUI view for both platforms — no platform-specific chrome, per
/// this repo's established "minimal" scope for these screens (mirrors
/// `DeadlinesView`). Read-only: nothing here is owner-editable.
///
/// On the shared Liquid Glass system since issue #71 — full-width glass
/// rows on `GlassScreenBackground()`, with every timestamp in this
/// chassis's monospaced digits so entries line up chronologically down the
/// page. No signature device and no screen accent: this screen's only
/// color is its signal-tinted outcome icons and its failure banner, both
/// computed from the same real failure signal as before.
public struct AutomationLogView: View {
    @ObservedObject private var viewModel: AutomationLogViewModel

    public init(viewModel: AutomationLogViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        AutomationLogContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `AutomationLogView` itself
/// so `.screenTheme(.liquidGlass)` (applied in that struct's body, above)
/// is genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct AutomationLogContent: View {
    @ObservedObject var viewModel: AutomationLogViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.entries.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    entryScroll
                }
            }
            .background(GlassScreenBackground())
            .navigationTitle("Automation Log")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    /// A `ScrollView` of `AutomationLogBubble`s rather than a `List` — this
    /// screen's whole point is liquid glass floating on plain white/black,
    /// which needs each row to draw its own translucent Material-backed
    /// shape (the shared `GlassBubble`) rather than a native list
    /// container's opaque row fill (mirrors `TasksView`'s own move from
    /// `List` to `ScrollView` + custom bubbles for the same reason).
    private var entryScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                if let mostRecentFailure = viewModel.mostRecentFailure {
                    failureBanner(mostRecentFailure)
                        .padding(.top, 18)
                }
                VStack(spacing: 14) {
                    ForEach(viewModel.entries) { entry in
                        AutomationLogBubble(entry: entry)
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
            StatusDot(viewModel.mostRecentFailure != nil ? .critical : .nominal)
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

    private var statusStripText: String {
        let count = viewModel.entries.count
        let noun = count == 1 ? "ENTRY" : "ENTRIES"
        return viewModel.mostRecentFailure != nil ? "\(count) \(noun)   ·   SYNC FAILED" : "\(count) \(noun)   ·   ALL CLEAR"
    }

    /// The "surfaced clearly" element this ticket asks for: unmissable at
    /// the top of the screen, distinct from an ordinary row, regardless of
    /// whether the failure itself is still recent enough to also appear in
    /// the roster below. Still a glass bubble — this screen gets no
    /// signature device of its own (issue #71) — with `signalRed` as the
    /// one deliberate accent, since the failure it reports is itself the
    /// meaning that color rule calls for.
    private func failureBanner(_ entry: AutomationLogEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            StatusDot(.critical)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("Most recent sync failure")
                    .pccPanelLabel()
                    .foregroundStyle(theme.signalRed(colorScheme))
                Text(entry.detail)
                    .font(.system(size: 14))
                Text(entry.occurredAt, style: .relative)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassBubble(.fullWidth)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Automation Activity Yet")
                .font(.headline)
            Text("Actions the system takes on its own, like a Calendar sync, will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Automation log bubble

/// One `AutomationLog` row: the shared `GlassBubble` surface (`.fullWidth`
/// size) with this screen's own content on it — an outcome glyph, the
/// action/detail text, and its relative timestamp in monospaced digits so
/// a column of rows lines up chronologically down the page. The bubble's
/// material, tint, specular highlight and rim come from `PCCChassis`, not
/// from here; only the layout is this screen's.
private struct AutomationLogBubble: View {
    let entry: AutomationLogEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            outcomeIcon
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.actionType)
                    .font(.system(size: 15, weight: .semibold))
                Text(entry.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Text(entry.occurredAt, style: .relative)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassBubble(Self.style)
    }

    @ViewBuilder
    private var outcomeIcon: some View {
        switch entry.outcome {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.signalGreen(colorScheme))
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.signalRed(colorScheme))
        }
    }
}
