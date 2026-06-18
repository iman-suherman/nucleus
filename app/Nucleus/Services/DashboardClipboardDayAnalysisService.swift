import Foundation
import NucleusKit
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum DashboardClipboardDayAnalysisService {
    static let analysisInterval: TimeInterval = DashboardAnalysisService.analysisInterval

    private static let logger = Logger(
        subsystem: "net.suherman.nucleus",
        category: "DashboardClipboardDayAnalysis"
    )
    private static let cacheKey = "nucleus.dashboard.clipboardDayAnalysisCache"

    private struct CachedAnalysis: Codable {
        var dayToken: TimeInterval
        var analysis: DashboardClipboardDayAnalysis
    }

    static func cachedAnalysis(now: Date = Date(), calendar: Calendar = .current) -> DashboardClipboardDayAnalysis? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedAnalysis.self, from: data),
              calendar.isDate(cached.analysis.analyzedAt, inSameDayAs: now),
              cached.dayToken == calendar.startOfDay(for: now).timeIntervalSince1970 else {
            return nil
        }
        return cached.analysis
    }

    static func shouldRefresh(lastAnalyzedAt: Date?, force: Bool, now: Date = Date()) -> Bool {
        if force { return true }
        guard let lastAnalyzedAt else { return true }
        return now.timeIntervalSince(lastAnalyzedAt) >= analysisInterval
    }

    static func resolveAnalysis(
        entries: [ClipboardEntry],
        snapshot: DashboardSnapshot,
        force: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> DashboardClipboardDayAnalysis {
        let lastAnalyzedAt = cachedAnalysis(now: now, calendar: calendar)?.analyzedAt

        if !shouldRefresh(lastAnalyzedAt: lastAnalyzedAt, force: force, now: now),
           let cached = cachedAnalysis(now: now, calendar: calendar) {
            return cached
        }

        let fallback = DashboardClipboardDayAnalysisEngine.fallback(
            entries: entries,
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )

        let resolved: DashboardClipboardDayAnalysis
        if #available(macOS 26.0, *) {
            resolved = (await appleIntelligenceAnalysis(
                entries: entries,
                snapshot: snapshot,
                fallback: fallback,
                now: now,
                calendar: calendar
            )) ?? fallback
        } else {
            resolved = fallback
        }

        cacheAnalysis(resolved, now: now, calendar: calendar)
        return resolved
    }

    @available(macOS 26.0, *)
    private static func appleIntelligenceAnalysis(
        entries: [ClipboardEntry],
        snapshot: DashboardSnapshot,
        fallback: DashboardClipboardDayAnalysis,
        now: Date,
        calendar: Calendar
    ) async -> DashboardClipboardDayAnalysis? {
#if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let context = DashboardClipboardDigestBuilder.buildPromptContext(
            entries: entries,
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )

        do {
            let session = LanguageModelSession(instructions: """
                You analyze clipboard captures for a personal productivity dashboard.
                Focus on productivity behavior — how the person works (context switching, fragmentation, app sources, capture pace), not generic advice.
                Base every statement on the provided clipboard entries and inferred work categories.
                Address the person directly as "you" — never say "the user" or "they".
                Do not invent tasks not supported by the clipboard data.
                Never repeat raw passwords or secrets — they are already redacted.
                Respond using exactly this format:

                SUMMARY:
                One or two sentences on today's clipboard behavior: dominant categories, app sources, and whether work looks focused or fragmented.

                INSIGHTS:
                - First data-driven productivity insight with numbers from the clipboard
                - Second insight about context switching, capture pace, or category concentration
                - Third insight if supported by the data

                IMPROVEMENTS:
                - First concrete habit change to improve productivity (include a number: minutes, count, or target)
                - Second improvement suggestion with a measurable target
                - Third improvement if warranted

                ACTIONS:
                - First clipboard-derived task with a number (count, minutes, or deadline)
                - Second clipboard-derived task with a number
                - Third clipboard-derived task with a number

                Provide 2 to 3 insights, 2 to 4 improvements, and 3 to 5 actions.
                Plain text only — no markdown, asterisks, bold, or headings.
                """)

            let response = try await session.respond(to: context)
            guard let parsed = DashboardClipboardDayAnalysisEngine.parseAIResponse(response.content) else {
                return nil
            }

            let todayCount = DashboardClipboardDigestBuilder.todayEntries(
                from: entries,
                now: now,
                calendar: calendar
            ).count

            let workGroups = DashboardClipboardDayAnalysisEngine.inferWorkGroups(
                from: entries,
                now: now,
                calendar: calendar
            )

            let insights = parsed.insights.isEmpty
                ? fallback.behaviorInsights
                : DashboardClipboardDayAnalysisEngine.nonEmptyDisplayLines(Array(parsed.insights.prefix(4)))
            let improvements = parsed.improvements.isEmpty
                ? fallback.improvementSuggestions
                : DashboardClipboardDayAnalysisEngine.nonEmptyDisplayLines(Array(parsed.improvements.prefix(5)))
            let actions = parsed.actions.isEmpty
                ? fallback.suggestedActions
                : DashboardClipboardDayAnalysisEngine.nonEmptyDisplayLines(Array(parsed.actions.prefix(5)))

            return DashboardClipboardDayAnalysis(
                daySummary: parsed.summary,
                keyProductivityHighlight: fallback.keyProductivityHighlight,
                behaviorInsights: insights,
                improvementSuggestions: improvements,
                suggestedActions: actions,
                workGroups: workGroups,
                todayCaptureCount: todayCount,
                analyzedAt: now
            )
        } catch {
            logger.error("Apple Intelligence clipboard day analysis failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
#else
        return nil
#endif
    }

    private static func cacheAnalysis(
        _ analysis: DashboardClipboardDayAnalysis,
        now: Date,
        calendar: Calendar
    ) {
        let cached = CachedAnalysis(
            dayToken: calendar.startOfDay(for: now).timeIntervalSince1970,
            analysis: analysis
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
