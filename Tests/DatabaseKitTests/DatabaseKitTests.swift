import XCTest
import SwiftData
import NucleusKit
@testable import DatabaseKit

final class DatabaseKitTests: XCTestCase {
    func testAccountRepositoryUpsert() throws {
        let container = try NucleusDatabase.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let account = GoogleAccount(email: "personal@gmail.com", displayName: "Personal", isPrimary: true)
        try AccountRepository.upsert(account, context: context)

        let fetched = try AccountRepository.fetchAll(context: context)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.email, "personal@gmail.com")
    }

    func testBillRepositoryUpsertAndPayment() throws {
        let container = try NucleusDatabase.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)

        let bill = Bill(
            name: "Electricity",
            amount: 120,
            recurrence: .monthly,
            dueDayOfMonth: 15,
            nextDueDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        )
        try BillRepository.upsert(bill, context: context)

        let payment = BillPayment(billID: bill.id, amount: 120)
        try BillRepository.insertPayment(payment, context: context)

        let bills = try BillRepository.fetchAll(context: context)
        let payments = try BillRepository.fetchPayments(context: context, billID: bill.id)

        XCTAssertEqual(bills.count, 1)
        XCTAssertEqual(bills.first?.name, "Electricity")
        XCTAssertEqual(payments.count, 1)
        XCTAssertEqual(payments.first?.amount, 120)
    }
}
