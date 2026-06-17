import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum DashboardPublicHolidayExplanationService {
    private static let logger = Logger(
        subsystem: "net.suherman.nucleus",
        category: "DashboardPublicHolidayExplanation"
    )
    private static let cacheKey = "nucleus.dashboard.publicHolidayExplanationCache"
    private static let maxCachedEntries = 32

    static func cachedExplanation(for holiday: DashboardNextPublicHoliday) -> String? {
        let cache = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String]
        return cache?[cacheToken(for: holiday)]
    }

    static func resolveExplanation(for holiday: DashboardNextPublicHoliday) async -> String {
        if let cached = cachedExplanation(for: holiday), !cached.isEmpty {
            return cached
        }

        let resolved: String
        if #available(macOS 26.0, *) {
            resolved = (await appleIntelligenceExplanation(for: holiday)) ?? fallbackExplanation(for: holiday)
        } else {
            resolved = fallbackExplanation(for: holiday)
        }

        cacheExplanation(resolved, for: holiday)
        return resolved
    }

    static func fallbackExplanation(for holiday: DashboardNextPublicHoliday) -> String {
        if let applicabilityLabel = holiday.applicabilityLabel {
            return "A public holiday \(applicabilityLabel.lowercased()), giving people time away from work to observe \(holiday.name)."
        }
        return "A nationwide public holiday in \(holiday.countryCode), giving people time away from work to observe \(holiday.name)."
    }

    @available(macOS 26.0, *)
    private static func appleIntelligenceExplanation(for holiday: DashboardNextPublicHoliday) async -> String? {
#if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let dateLabel = formatter.string(from: holiday.date)

        do {
            let session = LanguageModelSession(instructions: """
                You explain public holidays clearly and warmly for a personal dashboard.
                Write one or two short sentences (under 220 characters total).
                Mention what the holiday commemorates or why people observe it.
                Use plain language. No bullet points, markdown, or greeting.
                """)
            let response = try await session.respond(to: """
                Explain this upcoming public holiday to someone living in \(holiday.countryCode):

                Holiday: \(holiday.name)
                Date: \(dateLabel)
                Scope: \(holiday.isNationwide ? "Nationwide" : (holiday.applicabilityLabel ?? "Regional"))
                """)
            let explanation = sanitizeExplanation(response.content)
            return explanation.isEmpty ? nil : explanation
        } catch {
            logger.error("Apple Intelligence holiday explanation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
#else
        return nil
#endif
    }

    private static func sanitizeExplanation(_ raw: String) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        if text.count > 280 {
            text = String(text.prefix(277)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return text
    }

    private static func cacheToken(for holiday: DashboardNextPublicHoliday) -> String {
        "\(holiday.countryCode)|\(holiday.name)|\(holiday.date.timeIntervalSince1970)"
    }

    private static func cacheExplanation(_ explanation: String, for holiday: DashboardNextPublicHoliday) {
        guard !explanation.isEmpty else { return }
        var cache = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        cache[cacheToken(for: holiday)] = explanation
        if cache.count > maxCachedEntries {
            for key in cache.keys.prefix(cache.count - maxCachedEntries) {
                cache.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(cache, forKey: cacheKey)
    }
}
