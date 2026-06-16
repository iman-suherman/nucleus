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
            expectedIncome: 3000,
            reference: reference,
            calendar: calendar
        )

        XCTAssertEqual(summary.paidThisMonthCount, 1)
        XCTAssertEqual(summary.paidThisMonthAmount, 500, accuracy: 0.001)
        XCTAssertEqual(summary.okToSpend, 2500, accuracy: 0.001)
    }
}
