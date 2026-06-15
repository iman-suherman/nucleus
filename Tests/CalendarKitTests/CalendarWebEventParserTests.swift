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

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }
}
