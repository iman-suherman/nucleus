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

    func testCategorizesDevelopmentClipboard() {
        let entry = ClipboardEntry(content: "kubectl get pods", contentType: "command", tags: ["kubernetes"])
        XCTAssertEqual(DashboardInsightsEngine.categorize(entry), .development)
    }
}
