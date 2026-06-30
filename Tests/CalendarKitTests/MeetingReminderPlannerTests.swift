import XCTest
import NucleusKit
@testable import CalendarKit

final class MeetingReminderPlannerTests: XCTestCase {
    func testCreatesTwoMinuteReminder() {
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
        XCTAssertEqual(reminders.count, 1)
        guard let reminder = reminders.first else {
            return XCTFail("Expected a two-minute reminder")
        }
        XCTAssertEqual(reminder.kind, .twoMinutes)
        XCTAssertEqual(
            reminder.fireDate.timeIntervalSince1970,
            start.addingTimeInterval(-MeetingReminderPlanner.reminderLeadTime).timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testSkipsReminderWhenLessThanTwoMinutesAway() {
        let start = Date().addingTimeInterval(90)
        let event = CalendarEventSummary(
            id: "2",
            accountID: UUID(),
            title: "Quick sync",
            startDate: start,
            endDate: start.addingTimeInterval(900),
            accountEmail: "work@example.com"
        )

        let reminders = MeetingReminderPlanner.reminders(for: [event], now: Date())
        XCTAssertTrue(reminders.isEmpty)
    }

    func testGroupsEventsWithSameStartTime() {
        let start = Date().addingTimeInterval(900)
        let work = CalendarEventSummary(
            id: "work",
            accountID: UUID(),
            title: "Client call",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            meetingLink: "https://meet.google.com/work",
            accountEmail: "work@example.com"
        )
        let personal = CalendarEventSummary(
            id: "personal",
            accountID: UUID(),
            title: "Team sync",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            meetingLink: "https://meet.google.com/personal",
            accountEmail: "personal@gmail.com"
        )

        let grouped = MeetingReminderPlanner.eventsStartingTogether(with: work, in: [work, personal])
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped.map(\.accountEmail), ["personal@gmail.com", "work@example.com"])
    }
}
