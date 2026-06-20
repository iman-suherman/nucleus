import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

struct MusicSearchIntent: Sendable, Equatable {
    var catalogTerms: [String]
    var lyricsQuery: String?
    var usedSemanticExpansion: Bool
}

@MainActor
enum MusicSemanticSearchService {
    private static let logger = Logger(subsystem: "net.suherman.nucleus", category: "MusicSemanticSearch")

    static func resolveIntent(query: String) async -> MusicSearchIntent {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return MusicSearchIntent(catalogTerms: [], lyricsQuery: nil, usedSemanticExpansion: false)
        }

        if #available(macOS 26.0, *) {
            if let expanded = await appleIntelligenceIntent(for: trimmed) {
                return expanded
            }
        }

        return heuristicIntent(for: trimmed)
    }

    @available(macOS 26.0, *)
    private static func appleIntelligenceIntent(for query: String) async -> MusicSearchIntent? {
#if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(instructions: """
                You help search Apple Music from natural-language requests.
                Understand mood, theme, lyrics fragments, and song descriptions.
                Respond using exactly this format with no extra text:

                CATALOG: up to 3 comma-separated Apple Music search queries
                LYRICS: a short lyrics phrase to search, or NONE
                """)
            let response = try await session.respond(to: """
                User query: \(query)

                Examples:
                - "sad breakup song about moving on" -> CATALOG: breakup ballad, moving on heartbreak | LYRICS: NONE
                - "hari ini kita mulai" -> CATALOG: Raisa | LYRICS: hari ini kita mulai
                - "that song that goes hello from the other side" -> CATALOG: Adele Hello | LYRICS: hello from the other side
                """)
            if let parsed = parseStructuredResponse(response.content, originalQuery: query) {
                return parsed
            }
        } catch {
            logger.error("semantic search expansion failed: \(error.localizedDescription, privacy: .public)")
        }
#endif
        return nil
    }

    private static func parseStructuredResponse(_ raw: String, originalQuery: String) -> MusicSearchIntent? {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var catalogTerms: [String] = []
        var lyricsQuery: String?

        for line in lines {
            let upper = line.uppercased()
            if upper.hasPrefix("CATALOG:") {
                let value = String(line.dropFirst(8))
                catalogTerms = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } else if upper.hasPrefix("LYRICS:") {
                let value = String(line.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, value.uppercased() != "NONE" {
                    lyricsQuery = value
                }
            }
        }

        guard !catalogTerms.isEmpty || lyricsQuery != nil else { return nil }

        if lyricsQuery == nil, shouldTreatAsLyricsQuery(originalQuery) {
            lyricsQuery = originalQuery
        }

        return MusicSearchIntent(
            catalogTerms: uniqueTerms(catalogTerms),
            lyricsQuery: lyricsQuery,
            usedSemanticExpansion: true
        )
    }

    private static func heuristicIntent(for query: String) -> MusicSearchIntent {
        var catalogTerms: [String] = []
        var lyricsQuery: String?

        if let quoted = extractQuotedPhrase(from: query) {
            lyricsQuery = quoted
            catalogTerms.append(quoted)
        }

        let lower = query.lowercased()
        let moodTerms = moodCatalogTerms(for: lower)
        catalogTerms.append(contentsOf: moodTerms)

        if shouldTreatAsLyricsQuery(query) {
            lyricsQuery = lyricsQuery ?? query
        }

        if catalogTerms.isEmpty, looksLikeNaturalLanguageSongRequest(lower) {
            catalogTerms.append(query)
        }

        return MusicSearchIntent(
            catalogTerms: uniqueTerms(catalogTerms),
            lyricsQuery: lyricsQuery,
            usedSemanticExpansion: !moodTerms.isEmpty || lyricsQuery != nil
        )
    }

    private static func shouldTreatAsLyricsQuery(_ query: String) -> Bool {
        if extractQuotedPhrase(from: query) != nil { return true }

        let words = query.split(whereSeparator: \.isWhitespace)
        if words.count >= 4 { return true }

        let lower = query.lowercased()
        let lyricHints = [
            "that goes", "lyrics", "chorus", "verse", "sings", "line ",
            "tak perlu", "hari ini", "i want", "when you", "baby ",
        ]
        return lyricHints.contains(where: { lower.contains($0) })
    }

    private static func looksLikeNaturalLanguageSongRequest(_ lower: String) -> Bool {
        let hints = [
            "song about", "sounds like", "feels like", "something ", "music for",
            "playlist for", "upbeat", "chill", "sad", "happy", "romantic", "breakup",
        ]
        return hints.contains(where: { lower.contains($0) })
    }

    private static func moodCatalogTerms(for lower: String) -> [String] {
        var terms: [String] = []
        if lower.contains("breakup") || lower.contains("heartbreak") {
            terms.append("breakup heartbreak ballad")
        }
        if lower.contains("sad") || lower.contains("melanchol") {
            terms.append("sad ballad emotional")
        }
        if lower.contains("happy") || lower.contains("upbeat") || lower.contains("feel good") {
            terms.append("upbeat feel good pop")
        }
        if lower.contains("romantic") || lower.contains("love song") {
            terms.append("romantic love songs")
        }
        if lower.contains("chill") || lower.contains("relax") {
            terms.append("chill acoustic")
        }
        if lower.contains("workout") || lower.contains("gym") || lower.contains("run") {
            terms.append("workout energetic")
        }
        return terms
    }

    private static func extractQuotedPhrase(from query: String) -> String? {
        let patterns = ["\"", "“", "”", "'"]
        for open in patterns {
            guard let start = query.firstIndex(of: Character(open)) else { continue }
            let afterStart = query.index(after: start)
            let closeChars: [Character] = open == "'" ? ["'"] : ["\"", "“", "”"]
            for close in closeChars {
                if let end = query[afterStart...].firstIndex(of: close) {
                    let phrase = String(query[afterStart..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if phrase.count >= 3 { return phrase }
                }
            }
        }
        return nil
    }

    private static func uniqueTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for term in terms {
            let key = term.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(term)
        }
        return output
    }
}
