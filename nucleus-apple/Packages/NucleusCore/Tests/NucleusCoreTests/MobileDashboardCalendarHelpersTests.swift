import Foundation
import NucleusKit
import XCTest
@testable import NucleusCore

final class MobileDashboardCalendarHelpersTests: XCTestCase {
    func testUpcomingBirthdaysWithinSevenDaysIncludesTodayAndExcludesLater() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12))!
        let today = birthday(on: now, title: "Alex Johnson's Birthday")
        let inSixDays = birthday(
            on: calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: now))!,
            title: "Sam Lee's Birthday"
        )
        let inEightDays = birthday(
            on: calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now))!,
            title: "Pat Kim's Birthday"
        )

        let result = MobileDashboardCalendarHelpers.upcomingBirthdays(
            in: [today, inSixDays, inEightDays],
            now: now,
            withinDays: MobileDashboardCalendarHelpers.dashboardBirthdayHorizonDays
        )

        XCTAssertEqual(result.map(\.title), [today.title, inSixDays.title])
    }

    func testNextUpcomingBirthdaysReturnsAllNamesOnNearestDate() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12))!
        let day = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
        let first = birthday(on: day, title: "Zoe Adams's Birthday")
        let second = birthday(on: day, title: "Ben Adams's Birthday")
        let later = birthday(
            on: calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: now))!,
            title: "Cara Adams's Birthday"
        )

        let result = MobileDashboardCalendarHelpers.nextUpcomingBirthdays(
            in: [later, second, first],
            now: now,
            withinDays: 7
        )

        XCTAssertEqual(result.map(\.title).sorted(), [first.title, second.title].sorted())
    }

    private func birthday(on date: Date, title: String) -> CalendarEventSummary {
        CalendarEventSummary(
            id: UUID().uuidString,
            accountID: UUID(),
            title: title,
            startDate: date,
            endDate: date.addingTimeInterval(86_400),
            accountEmail: "Birthdays",
            isBirthday: true
        )
    }
}
