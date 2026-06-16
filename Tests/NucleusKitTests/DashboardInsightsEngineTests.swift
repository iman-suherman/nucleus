import XCTest
@testable import NucleusKit

final class DashboardInsightsEngineTests: XCTestCase {
    func testBuildsUpcomingBillsSummary() {
        let bill = Bill(
            name: "Internet",
            amount: 80,
            nextDueDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()
        )
        let snapshot = DashboardInsightsEngine.build(
            unreadMailCount: 2,
            unreadChatCount: 1,
            passwordCount: 3,
            notesCount: 5,
            bills: [bill],
            payments: [],
            clipboardEntries: [
                ClipboardEntry(content: "docker compose up", contentType: "command", tags: ["docker"]),
                ClipboardEntry(content: "https://meet.google.com/abc", contentType: "url", tags: ["meeting", "url"]),
            ]
        )

        XCTAssertEqual(snapshot.unreadMailCount, 2)
        XCTAssertEqual(snapshot.unreadChatCount, 1)
        XCTAssertEqual(snapshot.passwordCount, 3)
        XCTAssertEqual(snapshot.upcomingBills.count, 1)
        XCTAssertEqual(snapshot.upcomingBills.first?.name, "Internet")
        XCTAssertFalse(snapshot.activitySummary.isEmpty)
        XCTAssertFalse(snapshot.productivitySummary.isEmpty)
    }

    func testBillPaymentSummaryGroupsByCategoryAndCurrency() {
        let calendar = Calendar.current
        let dueDate = calendar.date(byAdding: .day, value: 5, to: Date()) ?? Date()
        let bills = [
            Bill(
                name: "Rent",
                amount: 2_000,
                currencyCode: "AUD",
                category: .housing,
                nextDueDate: dueDate
            ),
            Bill(
                name: "Electricity",
                amount: 180,
                currencyCode: "AUD",
                category: .utilities,
                nextDueDate: dueDate
            ),
            Bill(
                name: "Netflix",
                amount: 22,
                currencyCode: "USD",
                category: .subscription,
                nextDueDate: dueDate
            ),
        ]

        let summary = DashboardInsightsEngine.billPaymentSummary(
            bills: bills,
            payments: [],
            withinDays: 14
        )

        XCTAssertEqual(summary.groups.count, 3)
        XCTAssertTrue(summary.preparationNotes.contains("Prepare"))
        XCTAssertEqual(
            summary.groups.first(where: { $0.category == .housing })?.totalAmount,
            2_000
        )
    }

    func testCategorizesDevelopmentClipboard() {
        let entry = ClipboardEntry(content: "kubectl get pods", contentType: "command", tags: ["kubernetes"])
        XCTAssertEqual(DashboardInsightsEngine.categorize(entry), .development)
    }
}
