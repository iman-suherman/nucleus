import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

enum DashboardNewsMood: String, Equatable, Codable, CaseIterable {
    case uplifting
    case neutral
    case analytical
    case concerning
    case urgent

    var label: String {
        switch self {
        case .uplifting: return "Uplifting"
        case .neutral: return "Informative"
        case .analytical: return "Analytical"
        case .concerning: return "Concerning"
        case .urgent: return "Breaking"
        }
    }
}

struct DashboardNewsEnrichment: Equatable {
    var mood: DashboardNewsMood
    var readerSummary: String
    var moodExplanation: String
}

@MainActor
enum DashboardNewsAnalysisService {
    private static let logger = Logger(
        subsystem: "net.suherman.nucleus",
        category: "DashboardNewsAnalysis"
    )
    private static let cacheKey = "nucleus.dashboard.newsEnrichmentCache"
    private static let maxCachedEntries = 48

    static func cachedEnrichment(for headline: DashboardNewsHeadline) -> DashboardNewsEnrichment? {
        guard let cache = loadCache(),
              let entry = cache[cacheToken(for: headline)],
              let mood = DashboardNewsMood(rawValue: entry.mood) else {
            return nil
        }
        return DashboardNewsEnrichment(
            mood: mood,
            readerSummary: entry.readerSummary,
            moodExplanation: entry.moodExplanation
        )
    }

    static func resolveEnrichment(for headline: DashboardNewsHeadline) async -> DashboardNewsEnrichment {
        if let cached = cachedEnrichment(for: headline),
           !cached.readerSummary.isEmpty {
            return cached
        }

        let resolved: DashboardNewsEnrichment
        if #available(macOS 26.0, *) {
            resolved = (await appleIntelligenceEnrichment(for: headline)) ?? fallbackEnrichment(for: headline)
        } else {
            resolved = fallbackEnrichment(for: headline)
        }

        cacheEnrichment(resolved, for: headline)
        return resolved
    }

    static func fallbackEnrichment(for headline: DashboardNewsHeadline) -> DashboardNewsEnrichment {
        let mood = inferMood(title: headline.title, summary: headline.summary)
        let readerSummary = fallbackReaderSummary(for: headline)
        let moodExplanation = fallbackMoodExplanation(mood: mood, title: headline.title, summary: headline.summary)
        return DashboardNewsEnrichment(
            mood: mood,
            readerSummary: readerSummary,
            moodExplanation: moodExplanation
        )
    }

    static func cleanedTitle(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: " - ", options: .backwards) {
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private struct CacheEntry: Codable {
        var mood: String
        var readerSummary: String
        var moodExplanation: String
    }

    @available(macOS 26.0, *)
    private static func appleIntelligenceEnrichment(for headline: DashboardNewsHeadline) async -> DashboardNewsEnrichment? {
#if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let title = cleanedTitle(headline.title)
        let sourceSummary = headline.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let session = LanguageModelSession(instructions: """
                You help a busy person skim the news on a personal dashboard.
                Write in plain, warm language for a general reader.
                Do not use markdown, bullet points, or greetings.
                Keep each field concise and useful.
                """)
            let response = try await session.respond(to: """
                Analyze this news item and respond using exactly this format:

                MOOD: uplifting | neutral | analytical | concerning | urgent
                SUMMARY: Two short sentences explaining what happened and why it matters to an everyday reader.
                MOOD_NOTE: One short sentence explaining why this story feels uplifting, informative, analytical, concerning, or urgent.

                Headline: \(title)
                Source blurb: \(sourceSummary.isEmpty ? "Not provided." : sourceSummary)
                """)
            if let parsed = parseStructuredResponse(response.content, headline: headline) {
                return parsed
            }
        } catch {
            logger.error("Apple Intelligence news enrichment failed: \(error.localizedDescription, privacy: .public)")
        }
#endif
        return nil
    }

    private static func parseStructuredResponse(
        _ raw: String,
        headline: DashboardNewsHeadline
    ) -> DashboardNewsEnrichment? {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var mood: DashboardNewsMood?
        var summary: String?
        var moodNote: String?

        for line in lines {
            let upper = line.uppercased()
            if upper.hasPrefix("MOOD:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                mood = DashboardNewsMood(rawValue: value)
                    ?? DashboardNewsMood.allCases.first { value.contains($0.rawValue) }
            } else if upper.hasPrefix("SUMMARY:") {
                summary = sanitizeText(String(line.dropFirst(8)), limit: 320)
            } else if upper.hasPrefix("MOOD_NOTE:") || upper.hasPrefix("MOOD NOTE:") {
                let prefix = upper.hasPrefix("MOOD_NOTE:") ? 10 : 10
                moodNote = sanitizeText(String(line.dropFirst(prefix)), limit: 180)
            }
        }

        let resolvedMood = mood ?? inferMood(title: headline.title, summary: headline.summary)
        guard let readerSummary = summary?.nilIfEmpty ?? fallbackReaderSummary(for: headline).nilIfEmpty else {
            return nil
        }

        return DashboardNewsEnrichment(
            mood: resolvedMood,
            readerSummary: readerSummary,
            moodExplanation: moodNote?.nilIfEmpty
                ?? fallbackMoodExplanation(mood: resolvedMood, title: headline.title, summary: headline.summary)
        )
    }

    private static func inferMood(title: String, summary: String) -> DashboardNewsMood {
        let text = (title + " " + summary).lowercased()

        let urgentTokens = [
            "breaking", "urgent", "emergency", "live:", "just in", "dead", "killed", "shooting",
            "explosion", "earthquake", "evacuat", "attack", "crash", "wildfire", "cyclone", "terror",
        ]
        if urgentTokens.contains(where: { text.contains($0) }) {
            return .urgent
        }

        let concerningTokens = [
            "crisis", "warn", "warning", "threat", "decline", "recession", "inflation", "layoff",
            "scandal", "investigation", "protest", "conflict", "sanction", "outbreak", "shortage",
            "loss", "fail", "bankrupt", "debt", "strike", "controvers",
        ]
        if concerningTokens.contains(where: { text.contains($0) }) {
            return .concerning
        }

        let upliftingTokens = [
            "breakthrough", "celebrate", "celebration", "record", "success", "win", "wins", "hope",
            "recovery", "award", "hero", "donate", "donation", "peace deal", "milestone", "growth",
        ]
        if upliftingTokens.contains(where: { text.contains($0) }) {
            return .uplifting
        }

        let analyticalTokens = [
            "analysis", "explainer", "what to know", "what we know", "how ", "why ", "report",
            "outlook", "forecast", "review", "study", "data", "economy", "market", "policy",
        ]
        if analyticalTokens.contains(where: { text.contains($0) }) {
            return .analytical
        }

        return .neutral
    }

    private static func fallbackReaderSummary(for headline: DashboardNewsHeadline) -> String {
        let title = cleanedTitle(headline.title)
        let summary = headline.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        if !summary.isEmpty {
            let sentence = firstSentence(from: summary)
            if sentence.count >= 40 {
                return "In brief: \(sentence)"
            }
            return "In brief: \(title). \(sentence)"
        }

        return "In brief: \(title). Open the story for the full report and context."
    }

    private static func fallbackMoodExplanation(mood: DashboardNewsMood, title: String, summary: String) -> String {
        let topic = cleanedTitle(title)
        switch mood {
        case .uplifting:
            return "This feels uplifting because it highlights progress, relief, or a positive turn in \(topic.lowercased())."
        case .neutral:
            return "This is a straight news update — useful context without an especially heavy or celebratory tone."
        case .analytical:
            return "This reads analytical: it is less about shock and more about helping you understand what is changing."
        case .concerning:
            return "This feels concerning because it points to risk, pressure, or uncertainty around \(topic.lowercased())."
        case .urgent:
            return "This is marked breaking because the story is developing quickly and may need your attention soon."
        }
    }

    private static func firstSentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = trimmed.firstIndex(of: ".") {
            return String(trimmed[..<dot]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.count > 220 {
            return String(trimmed.prefix(217)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return trimmed
    }

    private static func sanitizeText(_ raw: String, limit: Int) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        if text.count > limit {
            text = String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return text
    }

    private static func cacheToken(for headline: DashboardNewsHeadline) -> String {
        headline.id
    }

    private static func loadCache() -> [String: CacheEntry]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([String: CacheEntry].self, from: data)
    }

    private static func cacheEnrichment(_ enrichment: DashboardNewsEnrichment, for headline: DashboardNewsHeadline) {
        guard !enrichment.readerSummary.isEmpty else { return }
        var cache = loadCache() ?? [:]
        cache[cacheToken(for: headline)] = CacheEntry(
            mood: enrichment.mood.rawValue,
            readerSummary: enrichment.readerSummary,
            moodExplanation: enrichment.moodExplanation
        )
        if cache.count > maxCachedEntries {
            for key in cache.keys.sorted().prefix(cache.count - maxCachedEntries) {
                cache.removeValue(forKey: key)
            }
        }
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
