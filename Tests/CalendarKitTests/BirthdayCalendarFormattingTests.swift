import XCTest
import NucleusKit
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

    func testDetailTooltipIncludesNameDateAndCalendar() {
        let birthday = CalendarEventSummary(
            id: "1",
            accountID: UUID(),
            title: "Alex Johnson's Birthday",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_086_400),
            accountEmail: "Birthdays",
            isBirthday: true
        )
        let tooltip = BirthdayCalendarFormatting.detailTooltip(for: birthday)
        XCTAssertTrue(tooltip.contains("Alex Johnson"))
        XCTAssertTrue(tooltip.contains("Birthdays"))
    }
}
