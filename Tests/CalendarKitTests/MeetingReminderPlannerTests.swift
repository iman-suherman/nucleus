import XCTest
import NucleusKit
@testable import CalendarKit

final class MeetingReminderPlannerTests: XCTestCase {
    func testCreatesTenAndOneMinuteReminders() {
        let start = Date().addingTimeInterval(900)
        let event = CalendarEventSummary(
            id: "1",
            accountID: UUID(),
            title: "Standup",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            accountEmail: "work@example.com"
        )

        let reminders = MeetingReminderPlanner.reminders(for: [event], now: Date())
        XCTAssertEqual(reminders.count, 2)
        XCTAssertTrue(reminders.contains { $0.kind == .tenMinutes })
        XCTAssertTrue(reminders.contains { $0.kind == .oneMinute })
    }
}
