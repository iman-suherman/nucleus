import CalendarKit
import NucleusKit
import XCTest

final class CalendarWebEventParserTests: XCTestCase {
    private let account = GoogleAccount(
        email: "test@example.com",
        displayName: "Test",
        isPrimary: true
    )

    func testParsesTimedEventLabel() {
        let reference = makeDate(year: 2026, month: 6, day: 15, hour: 8)
        let events = CalendarWebEventParser.parse(
            labels: ["Team sync, Monday, June 16, 9:00 AM – 10:00 AM"],
            account: account,
            now: reference
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Team sync")
    }

    func testParsesAllDayWorkingLocationLabel() {
        let reference = makeDate(year: 2026, month: 6, day: 15, hour: 8)
        let events = CalendarWebEventParser.parse(
            labels: ["Home, Monday, June 16"],
            account: account,
            now: reference
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Home")
    }

    func testParsesBareWorkingLocationTitle() {
        let reference = makeDate(year: 2026, month: 6, day: 15, hour: 8)
        let events = CalendarWebEventParser.parse(
            labels: ["Home"],
            account: account,
            now: reference
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testRejectsCalendarChromeLabels() {
        let reference = makeDate(year: 2026, month: 6, day: 15, hour: 8)
        let events = CalendarWebEventParser.parse(
            labels: [
                "Add a working location",
                "Add location, Monday, June 16",
                "Change working location, Suherman, 15 June 2026. Current location is Home",
                "Working location: Home, Suherman, 15 – 16 June 2026",
                "Work (Qantas)",
            ],
            account: account,
            now: reference
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testParsesSingleTimeEventLabel() {
        let reference = makeDate(year: 2026, month: 6, day: 15, hour: 8)
        let events = CalendarWebEventParser.parse(
            entries: [
                CalendarWebEventParser.Entry(
                    label: "Tech Backlog review, Monday, June 16, 2:00 PM – 3:00 PM",
                    start: "2:00 PM",
                    end: "3:00 PM"
                ),
            ],
            account: account,
            now: reference
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Tech Backlog review")
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }
}
