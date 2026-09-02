import Foundation

/// Holds the Deadlines screen's state and talks to the backend through a
/// `DeadlinesAPIClient` — kept separate from `DeadlinesView` so the view
/// stays a thin rendering of this state (mirrors `ProjectsViewModel`'s
/// split). Read-only: setting/clearing a Deadline happens on the Tasks and
/// Projects screens, not here — see `TasksViewModel`/`ProjectsViewModel`.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class DeadlinesViewModel: ObservableObject {
    @Published public private(set) var items: [DeadlineItem] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: DeadlinesAPIClient

    public init(client: DeadlinesAPIClient) {
        self.client = client
    }

    /// The backend already orders `items` by Deadline proximity with undated
    /// items included (`DeadlineController.index`) — this just fetches and
    /// stores that order as-is.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await client.listDeadlines()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Deadlines: \(error.localizedDescription)"
        }
    }

    /// Calendar-day difference between `referenceDate` and `item`'s due
    /// date — `nil` when `item` has no due date at all. Compares by
    /// calendar day, not a raw time-interval division, to avoid an
    /// off-by-one read near midnight a `/ 86400` would risk. Moved here off
    /// `DeadlinesView`'s prior `CountdownBadge` (issue #68) so it's
    /// unit-testable at this package's pure-logic test seam (`PCCUITests`)
    /// without needing a whole `DeadlinesViewModel` instance wired up with
    /// an API client. `referenceDate` defaults to `Date()` for every real
    /// call site; tests pass a fixed date instead so the result doesn't
    /// depend on when they happen to run.
    public static nonisolated func daysRemaining(for item: DeadlineItem, referenceDate: Date = Date()) -> Int? {
        guard let dueDate = item.dueDate else { return nil }
        let calendar = Calendar.current
        let startOfReference = calendar.startOfDay(for: referenceDate)
        let startOfDue = calendar.startOfDay(for: dueDate)
        return calendar.dateComponents([.day], from: startOfReference, to: startOfDue).day
    }

    /// Whether `item` is overdue: has a due date, isn't complete, and that
    /// due date has passed as of `referenceDate`. Compares the raw due-date
    /// instant against `referenceDate`, not `daysRemaining`'s calendar-day
    /// difference — matches this screen's pre-#68 behavior exactly (an item
    /// due earlier today already reads overdue, rather than waiting until
    /// tomorrow), even though that means an item can show "Today" in its
    /// countdown badge while `isOverdue` is already `true`.
    public static nonisolated func isOverdue(_ item: DeadlineItem, referenceDate: Date = Date()) -> Bool {
        guard let dueDate = item.dueDate, item.isComplete != true else { return false }
        return dueDate < referenceDate
    }

    /// The countdown badge's full rendering: a "3D" magnitude, its unit
    /// label ("Left"/"Today"/"Overdue"/"Done"), and the urgency tier that
    /// colors both — green past the 3-day mark, amber inside it (today
    /// included), red once overdue, and `.idle` once complete. `nil` when
    /// `item` has no due date, same as `daysRemaining`. Reuses
    /// `PanelStatus` rather than inventing a parallel color-tier enum —
    /// this badge's four states are exactly that vocabulary's "needs you
    /// now / worth a look / nothing to report / nominal."
    public static nonisolated func countdown(for item: DeadlineItem, referenceDate: Date = Date()) -> DeadlineCountdown? {
        guard let days = daysRemaining(for: item, referenceDate: referenceDate) else { return nil }
        let numberText = "\(abs(days))D"
        if item.isComplete == true {
            return DeadlineCountdown(numberText: numberText, unitText: "Done", status: .idle)
        }
        if days < 0 {
            return DeadlineCountdown(numberText: numberText, unitText: "Overdue", status: .critical)
        }
        if days == 0 {
            return DeadlineCountdown(numberText: numberText, unitText: "Today", status: .attention)
        }
        if days <= 3 {
            return DeadlineCountdown(numberText: numberText, unitText: "Left", status: .attention)
        }
        return DeadlineCountdown(numberText: numberText, unitText: "Left", status: .nominal)
    }
}

/// One Deadline row's countdown badge, fully rendered as data —
/// `DeadlinesViewModel.countdown(for:referenceDate:)`'s return type. A
/// plain `Equatable` value rather than computed inline in the badge view,
/// so the pure "what does this badge say" logic is unit-testable apart
/// from SwiftUI (issue #68).
public struct DeadlineCountdown: Equatable {
    public let numberText: String
    public let unitText: String
    public let status: PanelStatus

    public init(numberText: String, unitText: String, status: PanelStatus) {
        self.numberText = numberText
        self.unitText = unitText
        self.status = status
    }
}
