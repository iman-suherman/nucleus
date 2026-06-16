import Foundation

enum DashboardQuotes {
    static let storageKey = "nucleus.dashboard.quote"

    private static let quotes: [String] = {
        guard let url = Bundle.main.url(forResource: "DashboardQuotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String].self, from: data),
              !decoded.isEmpty
        else {
            return [fallbackQuote]
        }
        return decoded
    }()

    private static let fallbackQuote = "May your day be calm, focused, and full of small wins."

    static func currentOrRandom() -> String {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           quotes.contains(saved) {
            return saved
        }
        return pickRandom()
    }

    static func pickRandom(excluding current: String? = nil) -> String {
        guard quotes.count > 1 else { return quotes.first ?? fallbackQuote }

        var candidate = quotes.randomElement() ?? fallbackQuote
        if let current, candidate == current {
            for _ in 0..<8 {
                let next = quotes.randomElement() ?? fallbackQuote
                if next != current {
                    candidate = next
                    break
                }
            }
        }

        UserDefaults.standard.set(candidate, forKey: storageKey)
        return candidate
    }
}

enum DashboardDurationFormatting {
    static func ago(from date: Date, now: Date = Date()) -> String {
        formatDuration(now.timeIntervalSince(date))
    }

    static func until(_ date: Date, now: Date = Date()) -> String {
        formatDuration(max(0, date.timeIntervalSince(now)))
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return "\(minutes) min, \(seconds) sec."
        }
        return "\(seconds) sec."
    }
}
