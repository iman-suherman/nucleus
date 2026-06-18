import AppKit
import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum DashboardPublicHolidayIconService {
    private static let logger = Logger(
        subsystem: "net.suherman.nucleus",
        category: "DashboardPublicHolidayIcon"
    )
    private static let cacheKey = "nucleus.dashboard.publicHolidayIconCache"
    private static let maxCachedEntries = 48

    static func cachedSymbol(for holiday: DashboardNextPublicHoliday) -> String? {
        let cache = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String]
        guard let symbol = cache?[cacheToken(for: holiday)] else { return nil }
        return isValidSFSymbol(symbol) ? symbol : nil
    }

    static func resolveSymbol(for holiday: DashboardNextPublicHoliday) async -> String {
        if let cached = cachedSymbol(for: holiday) {
            return cached
        }

        let resolved: String
        if #available(macOS 26.0, *) {
            resolved = (await appleIntelligenceSymbol(for: holiday)) ?? fallbackSymbol(for: holiday)
        } else {
            resolved = fallbackSymbol(for: holiday)
        }

        cacheSymbol(resolved, for: holiday)
        return resolved
    }

    static func fallbackSymbol(for holiday: DashboardNextPublicHoliday) -> String {
        let name = holiday.name.lowercased()

        if name.contains("christmas") || name.contains("natal") {
            return "gift.fill"
        }
        if name.contains("easter") || name.contains("paskah") {
            return "leaf.fill"
        }
        if name.contains("new year") || name.contains("tahun baru") {
            return "sparkles"
        }
        if name.contains("labour") || name.contains("labor") || name.contains("worker") || name.contains("buruh") {
            return "hammer.fill"
        }
        if name.contains("queen") || name.contains("king") || name.contains("majesty") || name.contains("crown") {
            return "crown.fill"
        }
        if name.contains("memorial") || name.contains("remembrance") || name.contains("anzac") || name.contains("veteran") {
            return "flame.fill"
        }
        if name.contains("independence") || name.contains("national day") || name.contains("republic") {
            return "flag.fill"
        }
        if name.contains("thanksgiving") {
            return "fork.knife"
        }
        if name.contains("mother") || name.contains("father") || name.contains("family") {
            return "heart.fill"
        }
        if name.contains("good friday") || name.contains("religious") || name.contains("holy") {
            return "cross.fill"
        }
        if holiday.isNationwide {
            return "globe.americas.fill"
        }
        return "mappin.and.ellipse"
    }

    @available(macOS 26.0, *)
    private static func appleIntelligenceSymbol(for holiday: DashboardNextPublicHoliday) async -> String? {
#if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(instructions: """
                You pick SF Symbols for public holidays shown on a macOS dashboard.
                Respond with exactly one valid SF Symbol name in kebab-case (examples: gift.fill, flame.fill, crown.fill).
                Pick a symbol that visually matches the holiday theme — not a country flag.
                Output only the symbol name. No punctuation, markdown, or explanation.
                """)
            let response = try await session.respond(to: """
                Public holiday: \(holiday.name)
                Country: \(holiday.countryCode)
                Scope: \(holiday.isNationwide ? "Nationwide" : (holiday.applicabilityLabel ?? "Regional"))
                """)
            let symbol = sanitizeSymbol(response.content)
            guard isValidSFSymbol(symbol) else { return nil }
            return symbol
        } catch {
            logger.error("Apple Intelligence holiday icon failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
#else
        return nil
#endif
    }

    private static func sanitizeSymbol(_ raw: String) -> String {
        var symbol = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .lowercased()

        if let firstLine = symbol.split(separator: "\n").first {
            symbol = String(firstLine)
        }
        if let match = symbol.range(of: #"^[a-z0-9]+(?:\.[a-z0-9]+)*$"#, options: .regularExpression) {
            return String(symbol[match])
        }
        return "calendar.badge.clock"
    }

    static func isValidSFSymbol(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    static func cacheToken(for holiday: DashboardNextPublicHoliday) -> String {
        "\(holiday.countryCode)|\(holiday.name)|\(holiday.date.timeIntervalSince1970)"
    }

    private static func cacheSymbol(_ symbol: String, for holiday: DashboardNextPublicHoliday) {
        guard isValidSFSymbol(symbol) else { return }
        var cache = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        cache[cacheToken(for: holiday)] = symbol
        if cache.count > maxCachedEntries {
            for key in cache.keys.prefix(cache.count - maxCachedEntries) {
                cache.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(cache, forKey: cacheKey)
    }
}
