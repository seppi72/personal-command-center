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
        .glassScreenBackground()
    }

    private func row(for notification: NotificationItem) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.message)
                Text(notification.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
