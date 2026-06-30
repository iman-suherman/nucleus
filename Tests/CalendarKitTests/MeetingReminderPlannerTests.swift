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

    func testSchedulesImminentReminderWhenWithinTwoMinutes() {
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
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.kind, .twoMinutes)
    }

    func testDueRemindersFiresNearTwoMinuteMark() {
        let start = Date().addingTimeInterval(118)
        let event = CalendarEventSummary(
            id: "due",
            accountID: UUID(),
            title: "Standup",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            accountEmail: "work@example.com"
        )

        let due = MeetingReminderPlanner.dueReminders(for: [event], now: Date())
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.event.id, "due")
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
        let events = [work, personal]

        let grouped = MeetingReminderPlanner.eventsStartingTogether(with: work, in: events)
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped.map(\.accountEmail), ["personal@gmail.com", "work@example.com"])
        XCTAssertEqual(
            MeetingReminderPlanner.alertGroupKey(for: work, in: events),
            MeetingReminderPlanner.alertGroupKey(for: personal, in: events)
        )
    }

    func testDueRemindersDedupesOverlappingMeetings() {
        let start = Date().addingTimeInterval(118)
        let work = CalendarEventSummary(
            id: "work",
            accountID: UUID(),
            title: "Client call",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            accountEmail: "work@example.com"
        )
        let personal = CalendarEventSummary(
            id: "personal",
            accountID: UUID(),
            title: "Team sync",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            accountEmail: "personal@gmail.com"
        )

        let due = MeetingReminderPlanner.dueReminders(for: [work, personal], now: Date())
        XCTAssertEqual(due.count, 1)
    }

    func testUniqueRemindersDedupesOverlappingMeetings() {
        let start = Date().addingTimeInterval(900)
        let work = CalendarEventSummary(
            id: "work",
            accountID: UUID(),
            title: "Client call",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            accountEmail: "work@example.com"
        )
        let personal = CalendarEventSummary(
            id: "personal",
            accountID: UUID(),
            title: "Team sync",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            accountEmail: "personal@gmail.com"
        )

        let reminders = MeetingReminderPlanner.uniqueReminders(for: [work, personal], now: Date())
        XCTAssertEqual(reminders.count, 1)
    }
}
