import Foundation
import NucleusKit
import XCTest

final class BillDueReminderPlannerTests: XCTestCase {
    func testSchedulesConfiguredLeadTimesAtSevenAM() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = try makeDate("2026-06-16T08:00:00Z", calendar: calendar)
        let bill = Bill(
            name: "Rent",
            amount: 1000,
            nextDueDate: try makeDate("2026-07-01", calendar: calendar)
        )

        let reminders = BillDueReminderPlanner.reminders(
            bills: [bill],
            payments: [],
            configuration: BillDueReminderConfiguration(hour: 7),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(reminders.count, 4)
        XCTAssertTrue(reminders.contains(where: { $0.kind == .sevenDaysBefore }))
        XCTAssertTrue(reminders.contains(where: { $0.kind == .threeDaysBefore }))
        XCTAssertTrue(reminders.contains(where: { $0.kind == .oneDayBefore }))
        XCTAssertTrue(reminders.contains(where: { $0.kind == .dueDate }))

        let sevenDayReminder = reminders.first { $0.kind == .sevenDaysBefore }
        let fireDate = try XCTUnwrap(sevenDayReminder?.fireDate)
        XCTAssertEqual(calendar.component(.hour, from: fireDate), 7)
        XCTAssertEqual(calendar.component(.minute, from: fireDate), 0)
        XCTAssertEqual(
            calendar.startOfDay(for: fireDate),
            try makeDate("2026-06-24", calendar: calendar)
        )
    }

    func testSkipsFullyPaidBills() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let dueDate = try makeDate("2026-07-15", calendar: calendar)
        let bill = Bill(name: "Credit Card", amount: 100, nextDueDate: dueDate)
        let payment = BillPayment(
            billID: bill.id,
            amount: 100,
            paidAt: try makeDate("2026-06-15", calendar: calendar)
        )
        let now = try makeDate("2026-06-16", calendar: calendar)

        let reminders = BillDueReminderPlanner.reminders(
            bills: [bill],
            payments: [payment],
            configuration: .default,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(reminders.isEmpty)
    }

    func testRespectsDisabledLeadTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let bill = Bill(
            name: "Internet",
            amount: 80,
            nextDueDate: try makeDate("2026-07-10", calendar: calendar)
        )
        let now = try makeDate("2026-06-16", calendar: calendar)
        let configuration = BillDueReminderConfiguration(
            notifySevenDaysBefore: false,
            notifyThreeDaysBefore: false,
            notifyOneDayBefore: true,
            notifyOnDueDate: true
        )

        let reminders = BillDueReminderPlanner.reminders(
            bills: [bill],
            payments: [],
            configuration: configuration,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(reminders.map(\.kind), [.oneDayBefore, .dueDate])
    }

    private func makeDate(_ value: String, calendar: Calendar) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.timeZone = calendar.timeZone
        if value.contains("T") {
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssX"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return try XCTUnwrap(formatter.date(from: value))
    }
}
