import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
public enum DashboardQuoteEmojiService {
    private static let cacheKey = "nucleus.dashboard.quoteEmojiCache"
    private static let maxCachedQuotes = 64

    public static func cachedEmojis(for quote: String) -> String? {
        let cache = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String]
        return cache?[quote]
    }

    public static func resolveEmojis(for quote: String) async -> String {
        if let cached = cachedEmojis(for: quote), !cached.isEmpty {
            return cached
        }

        let resolved: String
        #if os(macOS)
        if #available(macOS 26.0, *) {
            resolved = (await appleIntelligenceEmojis(for: quote)) ?? keywordEmojis(for: quote)
        } else {
            resolved = keywordEmojis(for: quote)
        }
        #elseif os(iOS)
        if #available(iOS 26.0, *) {
            resolved = (await appleIntelligenceEmojis(for: quote)) ?? keywordEmojis(for: quote)
        } else {
            resolved = keywordEmojis(for: quote)
        }
        #else
        resolved = keywordEmojis(for: quote)
        #endif

        let sanitized = sanitizeEmojis(resolved)
        let emojis = sanitized.isEmpty ? keywordEmojis(for: quote) : sanitized
        cacheEmojis(emojis, for: quote)
        return emojis
    }

    public static func keywordEmojis(for quote: String) -> String {
        let lower = quote.lowercased()
        var matches: [String] = []

        func append(_ emoji: String) {
            guard !matches.contains(emoji), matches.count < 3 else { return }
            matches.append(emoji)
        }

        if lower.contains("laugh") || lower.contains("joy") || lower.contains("delight") {
            append("😄")
        }
        if lower.contains("gratitude") || lower.contains("thank") || lower.contains("kind") {
            append("🙏")
        }
        if lower.contains("calm") || lower.contains("peace") || lower.contains("quiet")
            || lower.contains("rest") || lower.contains("balance") {
            append("🌿")
        }
        if lower.contains("hope") || lower.contains("dream") || lower.contains("grow")
            || lower.contains("bloom") || lower.contains("fresh") {
            append("🌱")
        }
        if lower.contains("focus") || lower.contains("work") || lower.contains("progress")
            || lower.contains("momentum") || lower.contains("effort") {
            append("🎯")
        }
        if lower.contains("clarity") || lower.contains("clear") || lower.contains("insight")
            || lower.contains("plan") {
            append("💡")
        }
        if lower.contains("energy") || lower.contains("spark") || lower.contains("sun")
            || lower.contains("bright") {
            append("☀️")
        }
        if lower.contains("rain") || lower.contains("weather") || lower.contains("cloud") {
            append("🌤️")
        }
        if lower.contains("heart") || lower.contains("warm") || lower.contains("love") {
            append("💛")
        }

        if matches.isEmpty {
            return "✨"
        }
        return matches.joined()
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private static func appleIntelligenceEmojis(for quote: String) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(instructions: """
                You pick emoji that match inspirational daily quotes.
                Respond with one to three emoji characters only.
                No words, punctuation, numbers, or explanation.
                """)
            let response = try await session.respond(to: """
                Choose one to three emoji that match the mood and imagery of this quote:

                \(quote)
                """)
            let emojis = sanitizeEmojis(response.content)
            return emojis.isEmpty ? nil : emojis
        } catch {
            return nil
        }
    }
    #endif

    private static func sanitizeEmojis(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var emojis = ""
        var count = 0

        for character in trimmed {
            guard count < 3, character.isLikelyEmoji else { continue }
            emojis.append(character)
            count += 1
        }

        return emojis
    }

    private static func cacheEmojis(_ emojis: String, for quote: String) {
        guard !emojis.isEmpty else { return }
        var cache = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        cache[quote] = emojis
        if cache.count > maxCachedQuotes {
            for key in cache.keys.prefix(cache.count - maxCachedQuotes) {
                cache.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(cache, forKey: cacheKey)
    }
}

private extension Character {
    var isLikelyEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmoji && (scalar.value > 0x238C || scalar.properties.isEmojiPresentation)
        }
    }
}
