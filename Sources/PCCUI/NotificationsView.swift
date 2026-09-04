import SwiftUI

/// Minimal Mac/iOS screen for ticket #46: the owner's "needs you" queue
/// (`CONTEXT.md`'s Notification entry) — every open Notification, newest
/// first, dismissed via context menu — the same per-row destructive
/// action `PersonalCommitmentsView` already uses, rather than inventing a
/// second, redundant tap target for the same action. One shared SwiftUI
/// view for both platforms — no platform-specific chrome, per this repo's
/// established "minimal" scope for these screens (mirrors
/// `AutomationLogView`/`DeadlinesView`). Nothing here creates a
/// Notification — that's tickets #47/#48's automated sourcing job, not
/// owner input.
///
/// On the shared Liquid Glass system since issue #71 — full-width glass
/// rows on `GlassScreenBackground()`, with the timestamp in this chassis's
/// monospaced digits so entries line up chronologically down the page. No
/// signature device and no screen accent: this screen's only color is the
/// `attention` `StatusDot`, computed from the same outstanding-items signal
/// as before.
public struct NotificationsView: View {
    @ObservedObject private var viewModel: NotificationsViewModel

    public init(viewModel: NotificationsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NotificationsContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `NotificationsView` itself
/// so `.screenTheme(.liquidGlass)` (applied in that struct's body, above)
/// is genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct NotificationsContent: View {
    @ObservedObject var viewModel: NotificationsViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.notifications.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    notificationScroll
                }
            }
            .background(GlassScreenBackground())
            .navigationTitle("Notifications")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    /// A `ScrollView` of `NotificationBubble`s rather than a `List` — this
    /// screen's whole point is liquid glass floating on plain white/black,
    /// which needs each row to draw its own translucent Material-backed
    /// shape (the shared `GlassBubble`) rather than a native list
    /// container's opaque row fill (mirrors `DeadlinesView`'s own move from
    /// `List` to `ScrollView` + custom bubbles for the same reason).
    /// Dismissal moves from the old `List`'s swipe gesture onto each row's
    /// own context menu — a `ScrollView` has no `List`-style swipe gesture
    /// to give it for free (mirrors `CategoriesView`'s identical tradeoff).
    private var notificationScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                VStack(spacing: 14) {
                    ForEach(viewModel.notifications) { notification in
                        NotificationBubble(notification: notification)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await viewModel.dismiss(notification) }
                                } label: {
                                    Label("Dismiss", systemImage: "xmark.circle")
                                }
                            }
                    }
                }
                .padding(.top, 18)
            }
            .padding(PCCChassis.outerMargin)
        }
    }

    // MARK: - Status strip

    /// This screen *is* the "needs you" queue (`CONTEXT.md`'s Notification
    /// entry) — every open row already means "needs you," so the strip's
    /// `StatusDot` is `.attention` whenever it's non-empty rather than
    /// needing its own separate threshold.
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
        viewModel.notifications.isEmpty ? .nominal : .attention
    }

    private var statusStripText: String {
        let count = viewModel.notifications.count
        if count == 0 { return "NOTHING NEEDS YOU" }
        let noun = count == 1 ? "ITEM" : "ITEMS"
        return "\(count) \(noun) NEED YOU"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing Needs You")
                .font(.headline)
            Text("Items that need your attention, like an overdue Task, will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Notification bubble

/// One Notification row: the shared `GlassBubble` surface (`.fullWidth`
/// size) with this screen's own content on it — an `attention` `StatusDot`,
/// the message, and its relative timestamp in monospaced digits so a
/// column of rows lines up chronologically down the page. The bubble's
/// material, tint, specular highlight and rim come from `PCCChassis`, not
/// from here; only the layout is this screen's.
private struct NotificationBubble: View {
    let notification: NotificationItem

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StatusDot(.attention)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.message)
                    .font(.system(size: 15))
                Text(notification.createdAt, style: .relative)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassBubble(Self.style)
    }
}
