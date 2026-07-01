import CalendarKit
import NucleusKit
import XCTest

final class CalendarEventFormattingTests: XCTestCase {
    func testDurationLabelMinutes() {
        let event = makeEvent(
            start: date(2026, 7, 1, 9, 0),
            end: date(2026, 7, 1, 9, 30)
        )
        XCTAssertEqual(CalendarEventFormatting.durationLabel(for: event), "30 min")
    }

    func testDurationLabelHours() {
        let event = makeEvent(
            start: date(2026, 7, 1, 9, 0),
            end: date(2026, 7, 1, 10, 0)
        )
        XCTAssertEqual(CalendarEventFormatting.durationLabel(for: event), "1 hr")
    }

    func testDurationLabelHoursAndMinutes() {
        let event = makeEvent(
            start: date(2026, 7, 1, 9, 0),
            end: date(2026, 7, 1, 10, 30)
        )
        XCTAssertEqual(CalendarEventFormatting.durationLabel(for: event), "1 hr 30 min")
    }

    func testScheduleTimeAndDurationLabel() {
        let event = makeEvent(
            start: date(2026, 7, 1, 9, 0),
            end: date(2026, 7, 1, 9, 45)
        )
        let label = CalendarEventFormatting.scheduleTimeAndDurationLabel(for: event)
        XCTAssertTrue(label.contains("–"))
        XCTAssertTrue(label.hasSuffix("45 min"))
    }

    func testTimeUntilStartLabelMinutes() {
        let start = date(2026, 7, 1, 9, 30)
        let now = date(2026, 7, 1, 9, 0)
        XCTAssertEqual(CalendarEventFormatting.timeUntilStartLabel(for: start, now: now), "in 30 min")
    }

    func testTimeUntilStartLabelHoursAndMinutes() {
        let start = date(2026, 7, 1, 10, 30)
        let now = date(2026, 7, 1, 9, 0)
        XCTAssertEqual(CalendarEventFormatting.timeUntilStartLabel(for: start, now: now), "in 1 hr 30 min")
    }

    func testTimeUntilStartWithDurationLabel() {
        let event = makeEvent(
            start: date(2026, 7, 1, 9, 14),
            end: date(2026, 7, 1, 10, 14)
        )
        let now = date(2026, 7, 1, 9, 0)
        XCTAssertEqual(
            CalendarEventFormatting.timeUntilStartWithDurationLabel(for: event, now: now),
            "in 14 min for 1 hr"
        )
    }

    func testMeetingStartsInLabel() {
        let start = date(2026, 7, 1, 9, 2)
        let now = date(2026, 7, 1, 9, 0)
        XCTAssertEqual(CalendarEventFormatting.meetingStartsInLabel(for: start, now: now), "Meeting in 2 min")
    }

    private func makeEvent(start: Date, end: Date) -> CalendarEventSummary {
        CalendarEventSummary(
            id: "evt",
            accountID: UUID(),
            title: "Standup",
            startDate: start,
            endDate: end,
            accountEmail: "work@example.com"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
