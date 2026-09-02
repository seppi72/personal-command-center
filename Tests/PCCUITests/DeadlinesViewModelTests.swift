import Foundation
import Testing

@testable import PCCUI

/// Covers `DeadlinesViewModel.daysRemaining`, `.isOverdue`, and
/// `.countdown` — the pure logic this screen's view model owns since issue
/// #68 pulled it off `DeadlinesView`'s `CountdownBadge`. Every fixed date
/// below is noon UTC, well clear of any midnight boundary, so a
/// day-difference assertion can't flip on the machine running the test.
@Suite("DeadlinesViewModel")
struct DeadlinesViewModelTests {
    private func date(_ daysFromEpoch: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(daysFromEpoch) * 86_400)
    }

    private var referenceDate: Date { date(0) }

    private func item(dueDate: Date?, isComplete: Bool? = false) -> DeadlineItem {
        DeadlineItem(kind: .task, id: UUID(), title: "Test Deadline", dueDate: dueDate, isComplete: isComplete)
    }

    // MARK: - daysRemaining

    @Test("no due date has no days-remaining figure")
    func daysRemainingNoDueDate() {
        #expect(DeadlinesViewModel.daysRemaining(for: item(dueDate: nil), referenceDate: referenceDate) == nil)
    }

    @Test("counts by calendar day, not raw elapsed time")
    func daysRemainingCalendarDay() {
        let dueTomorrow = item(dueDate: date(1))
        #expect(DeadlinesViewModel.daysRemaining(for: dueTomorrow, referenceDate: referenceDate) == 1)
        let dueLastWeek = item(dueDate: date(-7))
        #expect(DeadlinesViewModel.daysRemaining(for: dueLastWeek, referenceDate: referenceDate) == -7)
        let dueToday = item(dueDate: date(0))
        #expect(DeadlinesViewModel.daysRemaining(for: dueToday, referenceDate: referenceDate) == 0)
    }

    // MARK: - isOverdue

    @Test("an item with no due date is never overdue")
    func isOverdueNoDueDate() {
        #expect(DeadlinesViewModel.isOverdue(item(dueDate: nil), referenceDate: referenceDate) == false)
    }

    @Test("an item due before the reference date is overdue")
    func isOverduePastDueDate() {
        let overdueItem = item(dueDate: referenceDate.addingTimeInterval(-3600))
        #expect(DeadlinesViewModel.isOverdue(overdueItem, referenceDate: referenceDate) == true)
    }

    @Test("an item due after the reference date is not overdue")
    func isOverdueFutureDueDate() {
        let upcomingItem = item(dueDate: referenceDate.addingTimeInterval(3600))
        #expect(DeadlinesViewModel.isOverdue(upcomingItem, referenceDate: referenceDate) == false)
    }

    @Test("a completed item is never overdue, even past its due date")
    func isOverdueCompletedPastDueDate() {
        let completedItem = item(dueDate: referenceDate.addingTimeInterval(-3600), isComplete: true)
        #expect(DeadlinesViewModel.isOverdue(completedItem, referenceDate: referenceDate) == false)
    }

    // MARK: - countdown

    @Test("no due date has no countdown badge")
    func countdownNoDueDate() {
        #expect(DeadlinesViewModel.countdown(for: item(dueDate: nil), referenceDate: referenceDate) == nil)
    }

    @Test("more than 3 days out reads green/nominal")
    func countdownFarOut() {
        let countdown = DeadlinesViewModel.countdown(for: item(dueDate: date(10)), referenceDate: referenceDate)
        #expect(countdown == DeadlineCountdown(numberText: "10D", unitText: "Left", status: .nominal))
    }

    @Test("within 3 days reads amber/attention")
    func countdownDueSoon() {
        let countdown = DeadlinesViewModel.countdown(for: item(dueDate: date(3)), referenceDate: referenceDate)
        #expect(countdown == DeadlineCountdown(numberText: "3D", unitText: "Left", status: .attention))
    }

    @Test("due today reads amber/attention, labeled Today")
    func countdownDueToday() {
        let countdown = DeadlinesViewModel.countdown(for: item(dueDate: date(0)), referenceDate: referenceDate)
        #expect(countdown == DeadlineCountdown(numberText: "0D", unitText: "Today", status: .attention))
    }

    @Test("past due reads red/critical, labeled Overdue")
    func countdownOverdue() {
        let countdown = DeadlinesViewModel.countdown(for: item(dueDate: date(-2)), referenceDate: referenceDate)
        #expect(countdown == DeadlineCountdown(numberText: "2D", unitText: "Overdue", status: .critical))
    }

    @Test("a completed item reads idle/Done regardless of its due date")
    func countdownComplete() {
        let countdown = DeadlinesViewModel.countdown(
            for: item(dueDate: date(-2), isComplete: true), referenceDate: referenceDate
        )
        #expect(countdown == DeadlineCountdown(numberText: "2D", unitText: "Done", status: .idle))
    }
}
