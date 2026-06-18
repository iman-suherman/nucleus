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

    func testDueWindowDisplayLabelIncludesRelativeDays() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let dueDate = calendar.date(byAdding: .day, value: 5, to: now) ?? now

        let label = DashboardInsightsEngine.dueWindowDisplayLabel(
            from: dueDate,
            to: dueDate,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(label.contains(NucleusFormatters.dayHeader.string(from: dueDate)))
        XCTAssertTrue(label.contains("Due in 5 days"))
    }

    func testCompanionSnapshotOmitsInboxAndChatMentions() {
        let snapshot = DashboardInsightsEngine.build(
            unreadMailCount: 0,
            unreadChatCount: 0,
            passwordCount: 2,
            notesCount: 4,
            bills: [],
            payments: [],
            clipboardEntries: [],
            includeCommunicationActivity: false,
            includeClipboardActivity: false
        )

        let summary = snapshot.activitySummary.joined(separator: " ")
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("inbox"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("chat"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("productivity"))
        XCTAssertTrue(summary.hasPrefix("You have "))
        XCTAssertTrue(snapshot.productivitySummary.isEmpty)
    }

    func testRedactsPasswordClipboardForAnalysis() {
        let entry = ClipboardEntry(
            content: "super-secret-password",
            contentType: "password",
            tags: ["password"]
        )
        XCTAssertEqual(
            DashboardClipboardDigestBuilder.sanitizedPreview(for: entry),
            "[redacted credential]"
        )
    }

    func testSanitizeDisplayTextStripsMarkdownAndThirdPersonVoice() {
        let sanitized = DashboardClipboardDayAnalysisEngine.sanitizeDisplayText(
            "**The user starts their day focused on communication.**"
        )
        XCTAssertFalse(sanitized.contains("*"))
        XCTAssertTrue(sanitized.hasPrefix("You "))
        XCTAssertTrue(sanitized.contains("your"))
    }

    func testFallbackDayAnalysisInfersDevelopmentWork() {
        let now = Date()
        let entries = [
            ClipboardEntry(
                content: "kubectl get pods",
                contentType: "command",
                tags: ["kubernetes"],
                capturedAt: now
            ),
        ]
        let snapshot = DashboardInsightsEngine.build(
            unreadMailCount: 4,
            unreadChatCount: 0,
            passwordCount: 0,
            notesCount: 0,
            bills: [],
            payments: [],
            clipboardEntries: entries,
            now: now
        )

        let analysis = DashboardClipboardDayAnalysisEngine.fallback(
            entries: entries,
            snapshot: snapshot,
            now: now
        )

        XCTAssertEqual(analysis.todayCaptureCount, 1)
        XCTAssertFalse(analysis.workGroups.isEmpty)
        XCTAssertEqual(analysis.workGroups.first?.category, .development)
        XCTAssertTrue(analysis.workGroups.first?.tasks.first?.localizedCaseInsensitiveContains("kubernetes") ?? false)
    }

    func testInferWorkGroupsFromCommunicationLinks() {
        let now = Date()
        let entries = [
            ClipboardEntry(
                content: "https://meet.google.com/abc-defg-hij",
                contentType: "url",
                tags: ["meeting", "url"],
                capturedAt: now
            ),
            ClipboardEntry(
                content: "https://example.com/doc",
                contentType: "url",
                tags: ["url"],
                capturedAt: now
            ),
        ]

        let groups = DashboardClipboardDayAnalysisEngine.inferWorkGroups(from: entries, now: now)
        XCTAssertEqual(groups.first?.category, .communication)
        XCTAssertEqual(groups.first?.captureCount, 2)
        XCTAssertFalse(groups.first?.tasks.isEmpty ?? true)
    }

    func testParsesAIAnalysisResponse() {
        let parsed = DashboardClipboardDayAnalysisEngine.parseAIResponse("""
            SUMMARY:
            **The user copied 12 items today focused on development.**

            INSIGHTS:
            - 8 of 12 captures were development commands from Terminal
            - Context switching is moderate across 3 apps

            IMPROVEMENTS:
            - Batch terminal commands in one 30-minute block
            - Reduce captures to under 5 per hour

            ACTIONS:
            - Spend 20 minutes clearing 5 of 12 unread emails
            - Block 30 minutes for coding tasks
            - Write 3 meeting action items before 5 PM
            """)

        XCTAssertNotNil(parsed)
        XCTAssertTrue(parsed?.summary.hasPrefix("You ") ?? false)
        XCTAssertFalse(parsed?.summary.contains("*") ?? true)
        XCTAssertEqual(parsed?.insights.count, 2)
        XCTAssertEqual(parsed?.improvements.count, 2)
        XCTAssertEqual(parsed?.actions.count, 3)
        XCTAssertTrue(parsed?.actions.first?.contains("20 minutes") ?? false)
    }

    func testNonEmptyDisplayLinesFiltersBlankBullets() {
        let parsed = DashboardClipboardDayAnalysisEngine.parseAIResponse("""
            SUMMARY:
            You copied 41 items today.

            INSIGHTS:
            - Notes & Drafts Dominance: You spend most of your time in notes.
            - Productivity Tools: You rely on Cursor and Chrome.
            - Workload Balance: You have a balanced workload.
            -
            •

            IMPROVEMENTS:
            - Time Management: Use a calendar block for deep work.
            -
            Suggestions to improve
            - Prioritization: Focus on the top 3 tasks first.
            """)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.insights.count, 3)
        XCTAssertEqual(parsed?.improvements.count, 2)
        XCTAssertTrue(
            DashboardClipboardDayAnalysisEngine.nonEmptyDisplayLines(parsed?.insights ?? [])
                .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }

    func testFallbackIncludesBehaviorInsightsAndImprovements() {
        let now = Date()
        var entries: [ClipboardEntry] = []
        for index in 0..<12 {
            entries.append(
                ClipboardEntry(
                    content: "Draft note snippet number \(index)",
                    contentType: "text",
                    sourceApplication: index % 2 == 0 ? "Cursor" : "ChatGPT",
                    tags: ["note"],
                    capturedAt: now.addingTimeInterval(TimeInterval(-index * 300))
                )
            )
        }

        let snapshot = DashboardInsightsEngine.build(
            unreadMailCount: 6,
            unreadChatCount: 0,
            passwordCount: 0,
            notesCount: 0,
            bills: [],
            payments: [],
            clipboardEntries: entries,
            now: now
        )

        let analysis = DashboardClipboardDayAnalysisEngine.fallback(
            entries: entries,
            snapshot: snapshot,
            now: now
        )

        XCTAssertEqual(analysis.todayCaptureCount, 12)
        XCTAssertFalse(analysis.behaviorInsights.isEmpty)
        XCTAssertFalse(analysis.improvementSuggestions.isEmpty)
        XCTAssertTrue(analysis.daySummary.contains("12"))
        XCTAssertFalse(analysis.workGroups.isEmpty)
    }

    func testDisplayExampleSkipsSensitiveCaptures() {
        let entries = [
            ClipboardEntry(content: "super-secret", contentType: "password", tags: ["password"]),
            ClipboardEntry(content: "kubectl get pods -n production", contentType: "command", tags: ["kubernetes"]),
        ]
        let example = DashboardClipboardDigestBuilder.displayExample(from: entries)
        XCTAssertNotNil(example)
        XCTAssertFalse(example?.contains("redacted") ?? true)
        XCTAssertTrue(example?.contains("kubectl") ?? false)
    }

    func testPasteReuseKeyProductivityHighlight() {
        let now = Date()
        let events = (0..<5).map { _ in
            ClipboardPasteReuseEvent(
                entryID: UUID(),
                contentType: "text",
                sourceApplication: "Cursor",
                category: .notesAndDrafts,
                reusedAt: now
            )
        }

        let highlight = ClipboardPasteReuseStore.keyProductivityHighlight(from: events, now: now)
        XCTAssertNotNil(highlight)
        XCTAssertTrue(highlight?.contains("Key productivity") ?? false)
        XCTAssertTrue(highlight?.contains("⇧⌘V") ?? false)

        let breakdown = ClipboardPasteReuseStore.categoryBreakdown(from: events)
        XCTAssertEqual(breakdown.first?.category, .notesAndDrafts)
        XCTAssertEqual(breakdown.first?.percentage, 100)
    }
}
