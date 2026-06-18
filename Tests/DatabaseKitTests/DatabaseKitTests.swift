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

    func testClipboardRepositoryRetainsSevenDaysAndPurgesOlderEntries() throws {
        let container = try NucleusDatabase.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 12))!

        let recent = ClipboardEntry(
            content: "recent clip",
            capturedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
        let expired = ClipboardEntry(
            content: "expired clip",
            capturedAt: calendar.date(byAdding: .day, value: -8, to: now)!
        )
        let pinnedExpired = ClipboardEntry(
            content: "pinned old clip",
            isPinned: true,
            capturedAt: calendar.date(byAdding: .day, value: -10, to: now)!
        )

        try ClipboardRepository.insert(recent, context: context, now: now, calendar: calendar)
        try ClipboardRepository.insert(expired, context: context, now: now, calendar: calendar)
        try ClipboardRepository.insert(pinnedExpired, context: context, now: now, calendar: calendar)

        let entries = try ClipboardRepository.fetchRecent(context: context, now: now, calendar: calendar)
        XCTAssertEqual(entries.map(\.content).sorted(), ["pinned old clip", "recent clip"])

        try ClipboardRepository.prune(context: context, now: now, calendar: calendar)
        let afterPrune = try ClipboardRepository.fetchRecent(context: context, now: now, calendar: calendar)
        XCTAssertEqual(afterPrune.map(\.content).sorted(), ["pinned old clip", "recent clip"])
        XCTAssertFalse(afterPrune.contains(where: { $0.content == "expired clip" }))
    }
}
