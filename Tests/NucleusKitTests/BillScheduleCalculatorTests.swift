import Foundation
import NucleusKit
import XCTest

final class BillScheduleCalculatorTests: XCTestCase {
    func testAdvanceMonthlyDueDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let due = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!

        let next = BillScheduleCalculator.advanceDueDate(
            from: due,
            recurrence: .monthly,
            customIntervalDays: nil,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.month, from: next), 7)
        XCTAssertEqual(calendar.component(.day, from: next), 1)
    }

    func testRemainingAmountUsesCurrentPeriodPayments() {
        let billID = UUID()
        let calendar = Calendar(identifier: .gregorian)
        let nextDue = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let bill = Bill(
            id: billID,
            name: "Internet",
            amount: 100,
            recurrence: .monthly,
            dueDayOfMonth: 1,
            nextDueDate: nextDue
        )

        let payments = [
            BillPayment(billID: billID, amount: 40, paidAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!),
        ]

        XCTAssertEqual(BillScheduleCalculator.remainingAmount(bill: bill, payments: payments, calendar: calendar), 60, accuracy: 0.001)
    }

    func testMonthlySummaryCountsPaidBills() {
        let billID = UUID()
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!
        let bill = Bill(
            id: billID,
            name: "Rent",
            amount: 500,
            recurrence: .monthly,
            dueDayOfMonth: 20,
            nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        )
        let payment = BillPayment(
            billID: billID,
            amount: 500,
            paidAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        )

        let summary = BillScheduleCalculator.monthlySummary(
            bills: [bill],
            payments: [payment],
            reference: reference,
            calendar: calendar
        )

        XCTAssertEqual(summary.byCurrency.first?.paidThisMonthAmount ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(summary.byCurrency.first?.currencyCode, "AUD")
    }

    func testDueWithinDaysOrOverdueCountIncludesOverdueAndUpcoming() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!

        let overdueID = UUID()
        let dueTodayID = UUID()
        let dueInTwoDaysID = UUID()
        let dueInFiveDaysID = UUID()
        let paidID = UUID()

        let bills = [
            Bill(
                id: overdueID,
                name: "Overdue",
                amount: 100,
                recurrence: .monthly,
                dueDayOfMonth: 1,
                nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
            ),
            Bill(
                id: dueTodayID,
                name: "Due Today",
                amount: 80,
                recurrence: .monthly,
                dueDayOfMonth: 16,
                nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!
            ),
            Bill(
                id: dueInTwoDaysID,
                name: "Due Soon",
                amount: 50,
                recurrence: .monthly,
                dueDayOfMonth: 18,
                nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!
            ),
            Bill(
                id: dueInFiveDaysID,
                name: "Later",
                amount: 40,
                recurrence: .monthly,
                dueDayOfMonth: 21,
                nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 21))!
            ),
            Bill(
                id: paidID,
                name: "Paid",
                amount: 90,
                recurrence: .monthly,
                dueDayOfMonth: 16,
                nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!
            ),
        ]

        let payments = [
            BillPayment(
                billID: paidID,
                amount: 90,
                paidAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
            ),
        ]

        let count = BillScheduleCalculator.dueWithinDaysOrOverdueCount(
            bills: bills,
            payments: payments,
            withinDays: 3,
            reference: reference,
            calendar: calendar
        )

        XCTAssertEqual(count, 3)
    }

    func testDueAccentUsesGreenWithinFifteenDaysAndRedWhenOverdue() {
        let calmGreen = BillScheduleCalculator.dueAccent(daysUntilDue: 20, isPaid: false)
        XCTAssertEqual(calmGreen.green, 201 / 255, accuracy: 0.01)

        let nearDue = BillScheduleCalculator.dueAccent(daysUntilDue: 7, isPaid: false)
        XCTAssertGreaterThan(nearDue.red, calmGreen.red)
        XCTAssertLessThan(nearDue.green, calmGreen.green)

        let overdue = BillScheduleCalculator.dueAccent(daysUntilDue: -2, isPaid: false)
        XCTAssertEqual(overdue.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(overdue.green, 0.23, accuracy: 0.01)
    }

    func testDueCountdownUsesExactDayCounts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!
        let due = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!

        XCTAssertEqual(
            BillScheduleCalculator.dueCountdown(for: due, from: reference, calendar: calendar),
            "Due in 15 days"
        )
    }

    func testSortedActiveBillsByDueDateOrdersByNextDueDate() {
        let calendar = Calendar(identifier: .gregorian)
        let overdue = Bill(
            name: "Overdue",
            amount: 100,
            nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        )
        let dueSoon = Bill(
            name: "Due Soon",
            amount: 80,
            nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!
        )
        let later = Bill(
            name: "Later",
            amount: 50,
            nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 25))!
        )
        let archived = Bill(
            name: "Archived",
            amount: 40,
            nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 12))!,
            isArchived: true
        )

        let sorted = BillScheduleCalculator.sortedActiveBillsByDueDate(
            [later, archived, overdue, dueSoon],
            calendar: calendar
        )

        XCTAssertEqual(sorted.map(\.name), ["Overdue", "Due Soon", "Later"])
    }

    func testIsDueWithinNotificationWindowIncludesOverdueAndThreeDayHorizon() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!

        let overdue = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let dueInThreeDays = calendar.date(from: DateComponents(year: 2026, month: 6, day: 19))!
        let dueInFourDays = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!

        XCTAssertTrue(
            BillScheduleCalculator.isDueWithinNotificationWindow(for: overdue, reference: reference, calendar: calendar)
        )
        XCTAssertTrue(
            BillScheduleCalculator.isDueWithinNotificationWindow(for: dueInThreeDays, reference: reference, calendar: calendar)
        )
        XCTAssertFalse(
            BillScheduleCalculator.isDueWithinNotificationWindow(for: dueInFourDays, reference: reference, calendar: calendar)
        )
    }
}
