import Foundation
import Testing

@testable import PCCUI

/// Covers `TasksViewModel.isOverdue(_:referenceDate:)` — the one piece of
/// pure logic this screen's view model owns (issue #68). Every other
/// `TasksViewModel` method touches a `TasksAPIClient`/`ProjectsAPIClient`/
/// `CoursesAPIClient` and stays outside this pure-logic seam, same as the
/// rest of `PCCUITests`.
@Suite("TasksViewModel.isOverdue")
struct TasksViewModelTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func task(dueDate: Date?, isComplete: Bool = false) -> PCCTask {
        PCCTask(id: UUID(), title: "Test Task", isComplete: isComplete, dueDate: dueDate)
    }

    @Test("a Task with no due date is never overdue")
    func noDueDate() {
        #expect(TasksViewModel.isOverdue(task(dueDate: nil), referenceDate: referenceDate) == false)
    }

    @Test("a Task due before the reference date is overdue")
    func pastDueDate() {
        let overdueTask = task(dueDate: referenceDate.addingTimeInterval(-3600))
        #expect(TasksViewModel.isOverdue(overdueTask, referenceDate: referenceDate) == true)
    }

    @Test("a Task due after the reference date is not overdue")
    func futureDueDate() {
        let upcomingTask = task(dueDate: referenceDate.addingTimeInterval(3600))
        #expect(TasksViewModel.isOverdue(upcomingTask, referenceDate: referenceDate) == false)
    }

    @Test("a completed Task is never overdue, even past its due date")
    func completedPastDueDate() {
        let completedTask = task(dueDate: referenceDate.addingTimeInterval(-3600), isComplete: true)
        #expect(TasksViewModel.isOverdue(completedTask, referenceDate: referenceDate) == false)
    }
}
