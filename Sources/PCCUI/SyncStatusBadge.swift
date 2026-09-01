import SwiftUI

/// The small trailing badge on a Personal Commitment row showing whether
/// it's synced to CalDAV, still syncing, or failed to sync — the visible
/// piece of spec #1's "clear, visible error state" requirement (user story
/// 26). Shared by `PersonalCommitmentsView` and `CalendarView` so the two
/// screens can't quietly drift on what this badge looks like.
struct SyncStatusBadge: View {
    let syncStatus: PersonalCommitment.SyncStatus

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        switch syncStatus {
        case .synced:
            EmptyView()
        case .failed:
            Label("Sync failed", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(theme.signalRed(colorScheme))
        case .pending:
            Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
    }
}
