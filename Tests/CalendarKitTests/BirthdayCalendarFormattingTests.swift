import XCTest
@testable import CalendarKit

final class BirthdayCalendarFormattingTests: XCTestCase {
    func testStripsPossessiveBirthdaySuffix() {
        XCTAssertEqual(
            BirthdayCalendarFormatting.displayName(from: "Alex Johnson's Birthday"),
            "Alex Johnson"
        )
    }

    func testStripsPlainBirthdaySuffix() {
        XCTAssertEqual(
            BirthdayCalendarFormatting.displayName(from: "Alex Johnson Birthday"),
            "Alex Johnson"
        )
    }

    func testKeepsTitleWhenNoBirthdaySuffix() {
        XCTAssertEqual(
            BirthdayCalendarFormatting.displayName(from: "Alex Johnson"),
            "Alex Johnson"
        )
    }
}
