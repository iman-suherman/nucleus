import CalendarKit
import NucleusKit
import XCTest

final class CalendarEventParserTests: XCTestCase {
    private let account = GoogleAccount(
        email: "work@example.com",
        displayName: "Work",
        isPrimary: true
    )

    func testParsesTimedEventWithTimeZoneOffset() {
        let payload: [String: Any] = [
            "id": "abc123",
            "summary": "Group Tech Town Hall",
            "start": ["dateTime": "2026-06-16T16:00:00+10:00"],
            "end": ["dateTime": "2026-06-16T17:00:00+10:00"],
        ]

        let event = CalendarEventParser.parse(payload, account: account)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.title, "Group Tech Town Hall")
    }

    func testSkipsWorkingLocationEvents() {
        let payload: [String: Any] = [
            "id": "loc123",
            "summary": "Office",
            "eventType": "workingLocation",
            "start": ["date": "2026-06-16"],
            "end": ["date": "2026-06-17"],
        ]

        XCTAssertNil(CalendarEventParser.parse(payload, account: account))
    }

    func testSkipsCalendarChromeTitles() {
        let payload: [String: Any] = [
            "id": "junk123",
            "summary": "Add a working location",
            "start": ["dateTime": "2026-06-16T00:00:00+10:00"],
            "end": ["dateTime": "2026-06-16T01:00:00+10:00"],
        ]

        XCTAssertNil(CalendarEventParser.parse(payload, account: account))
    }

    func testSkipsChangeWorkingLocationChromeTitles() {
        let payload: [String: Any] = [
            "id": "junk456",
            "summary": "Change working location",
            "start": ["dateTime": "2026-06-16T00:00:00+10:00"],
            "end": ["dateTime": "2026-06-16T01:00:00+10:00"],
        ]

        XCTAssertNil(CalendarEventParser.parse(payload, account: account))
    }
}
