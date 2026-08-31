import SwiftUI

/// Minimal Mac/iOS screen for ticket #46: the owner's "needs you" queue
/// (`CONTEXT.md`'s Notification entry) — every open Notification, newest
/// first, dismissed via swipe-to-delete — the same per-row destructive
/// action `PersonalCommitmentsView` already uses, rather than inventing a
/// second, redundant tap target for the same action. One shared SwiftUI
/// view for both platforms — no platform-specific chrome, per this repo's
/// established "minimal" scope for these screens (mirrors
/// `AutomationLogView`/`DeadlinesView`). Nothing here creates a
/// Notification — that's tickets #47/#48's automated sourcing job, not
/// owner input.
public struct NotificationsView: View {
    @ObservedObject private var viewModel: NotificationsViewModel

    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: NotificationsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.notifications.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    notificationList
                }
            }
            .navigationTitle("Notifications")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    private var notificationList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.notifications) { notification in
                    row(for: notification)
                }
                .onDelete { offsets in
                    let toDismiss = offsets.map { viewModel.notifications[$0] }
                    Task {
                        for notification in toDismiss {
                            await viewModel.dismiss(notification)
                        }
                    }
                }
                .glassRows()
            }
        }
        .glassScreenBackground()
    }

    private func row(for notification: NotificationItem) -> some View {
        HStack(alignment: .top) {
            StatusDot(.attention)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.message)
                Text(notification.createdAt, style: .relative)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
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
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(GlassStyle.panelLine(for: colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
