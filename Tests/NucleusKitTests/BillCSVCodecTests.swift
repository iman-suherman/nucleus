import Foundation
import NucleusKit
import XCTest

final class BillCSVCodecTests: XCTestCase {
    func testImportSampleBillsAndPayments() {
        let csv = """
        type,name,amount,category,recurrence,custom_interval_days,due_day_of_month,next_due_date,notes,archived,bill_name,paid_at,payment_amount,payment_note
        bill,AU: Pay St George Mortgages,1000.00,housing,monthly,,1,2026-07-01,,false,,,,
        payment,,,,,,,,,,AU: Pay St George Mortgages,2026-06-01T10:00:00Z,1000.00,June mortgage
        """

        let parsed = BillCSVCodec.importCSV(csv)
        XCTAssertEqual(parsed.bills.count, 1)
        XCTAssertEqual(parsed.payments.count, 1)
        XCTAssertEqual(parsed.bills.first?.name, "AU: Pay St George Mortgages")
        XCTAssertEqual(parsed.payments.first?.amount, 1000)
        XCTAssertTrue(parsed.result.errors.isEmpty)
    }

    func testExportRoundTripPreservesBillName() {
        let bill = Bill(
            name: "Internet",
            amount: 90,
            recurrence: .monthly,
            dueDayOfMonth: 12,
            nextDueDate: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        )
        let payment = BillPayment(billID: bill.id, amount: 90, paidAt: Date(timeIntervalSince1970: 1_718_000_000))

        let csv = BillCSVCodec.exportCSV(bills: [bill], payments: [payment])
        let imported = BillCSVCodec.importCSV(csv)

        XCTAssertEqual(imported.bills.first?.name, "Internet")
        XCTAssertEqual(imported.payments.count, 1)
    }
}

final class BillDisplayStatusTests: XCTestCase {
    func testPaidStatusWhenFullyPaidThisPeriod() {
        let billID = UUID()
        let bill = Bill(
            id: billID,
            name: "Rent",
            amount: 500,
            recurrence: .monthly,
            dueDayOfMonth: 1,
            nextDueDate: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        )
        let payment = BillPayment(
            billID: billID,
            amount: 500,
            paidAt: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        )

        XCTAssertEqual(
            BillScheduleCalculator.displayStatus(bill: bill, payments: [payment]),
            .paid
        )
    }

    func testOverdueStatusWhenPastDueAndUnpaid() {
        let bill = Bill(
            name: "Water",
            amount: 80,
            recurrence: .monthly,
            dueDayOfMonth: 1,
            nextDueDate: Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        )
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 16))!

        XCTAssertEqual(
            BillScheduleCalculator.displayStatus(bill: bill, payments: [], reference: reference),
            .overdue
        )
    }
}
