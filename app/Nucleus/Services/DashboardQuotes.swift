import Foundation
import NucleusKit

enum DashboardTimePeriod {
    case morning, afternoon, evening, night

    static func current(now: Date = Date(), calendar: Calendar = .current) -> DashboardTimePeriod {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }
}

enum DashboardQuoteSchedule: String {
    case weekday, leisure
}

enum DashboardQuotes {
    static let storageKey = "nucleus.dashboard.quote"
    static let contextKey = "nucleus.dashboard.quote.context"

    struct Context: Equatable {
        let schedule: DashboardQuoteSchedule
        let period: DashboardTimePeriod

        var storageToken: String {
            "\(schedule.rawValue).\(periodToken)"
        }

        private var periodToken: String {
            switch period {
            case .morning: return "morning"
            case .afternoon: return "afternoon"
            case .evening: return "evening"
            case .night: return "night"
            }
        }

        static func current(isPublicHoliday: Bool = false) -> Context {
            let schedule: DashboardQuoteSchedule
            if DashboardGreeting.isWeekend() || isPublicHoliday {
                schedule = .leisure
            } else {
                schedule = .weekday
            }
            return Context(schedule: schedule, period: DashboardTimePeriod.current())
        }
    }

    private struct QuoteLibrary: Decodable {
        let weekday: PeriodQuotes
        let leisure: PeriodQuotes
    }

    private struct PeriodQuotes: Decodable {
        let morning: [String]
        let afternoon: [String]
        let evening: [String]
        let night: [String]

        func quotes(for period: DashboardTimePeriod) -> [String] {
            switch period {
            case .morning: return morning
            case .afternoon: return afternoon
            case .evening: return evening
            case .night: return night
            }
        }
    }

    private static let library: QuoteLibrary = {
        guard let url = Bundle.main.url(forResource: "DashboardQuotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(QuoteLibrary.self, from: data)
        else {
            return QuoteLibrary(
                weekday: PeriodQuotes(
                    morning: [fallbackQuote],
                    afternoon: [fallbackQuote],
                    evening: [fallbackQuote],
                    night: [fallbackQuote]
                ),
                leisure: PeriodQuotes(
                    morning: [fallbackQuote],
                    afternoon: [fallbackQuote],
                    evening: [fallbackQuote],
                    night: [fallbackQuote]
                )
            )
        }
        return decoded
    }()

    private static let fallbackQuote = "May your path be calm, focused, and full of small wins."

    static func currentOrRandom(isPublicHoliday: Bool = false) -> String {
        let context = Context.current(isPublicHoliday: isPublicHoliday)
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           UserDefaults.standard.string(forKey: contextKey) == context.storageToken,
           quotes(for: context).contains(saved) {
            return saved
        }
        return pickRandom(excluding: nil, context: context)
    }

    @discardableResult
    static func refreshIfContextChanged(
        excluding current: String? = nil,
        isPublicHoliday: Bool = false
    ) -> String? {
        let context = Context.current(isPublicHoliday: isPublicHoliday)
        let savedContext = UserDefaults.standard.string(forKey: contextKey)
        if savedContext == context.storageToken,
           let current,
           quotes(for: context).contains(current) {
            return nil
        }
        return pickRandom(excluding: current, context: context)
    }

    static func pickRandom(excluding current: String? = nil, isPublicHoliday: Bool = false) -> String {
        pickRandom(excluding: current, context: Context.current(isPublicHoliday: isPublicHoliday))
    }

    @discardableResult
    private static func pickRandom(excluding current: String?, context: Context) -> String {
        let pool = quotes(for: context)
        guard !pool.isEmpty else { return fallbackQuote }

        var candidate = pool.randomElement() ?? fallbackQuote
        if let current, candidate == current, pool.count > 1 {
            for _ in 0..<8 {
                let next = pool.randomElement() ?? fallbackQuote
                if next != current {
                    candidate = next
                    break
                }
            }
        }

        UserDefaults.standard.set(candidate, forKey: storageKey)
        UserDefaults.standard.set(context.storageToken, forKey: contextKey)
        return candidate
    }

    private static func quotes(for context: Context) -> [String] {
        switch context.schedule {
        case .weekday:
            return library.weekday.quotes(for: context.period)
        case .leisure:
            return library.leisure.quotes(for: context.period)
        }
    }

    static func quoteBody(from quote: String) -> String {
        var text = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        while text.hasSuffix(".") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    static func displayBody(from quote: String, emojis: String) -> String {
        let body = quoteBody(from: quote)
        let trimmedEmojis = emojis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmojis.isEmpty else { return body }
        return "\(body) \(trimmedEmojis) "
    }

    static func theme(for quote: String) -> String {
        let lower = quote.lowercased()

        if lower.contains("work") || lower.contains("focus") || lower.contains("effort")
            || lower.contains("momentum") || lower.contains("progress") {
            if lower.contains("heart") || lower.contains("kind") || lower.contains("gentle") {
                return "About letting meaningful work guide your priorities with warmth."
            }
            return "About meaningful work, focus, and steady progress."
        }

        if lower.contains("calm") || lower.contains("peace") || lower.contains("rest")
            || lower.contains("balance") || lower.contains("quiet") || lower.contains("breath") {
            return "About calm, balance, and making space to breathe."
        }

        if lower.contains("gratitude") || lower.contains("thank") || lower.contains("kindness")
            || lower.contains("generous") || lower.contains("warm") {
            return "About gratitude, kindness, and appreciating the day."
        }

        if lower.contains("hope") || lower.contains("dream") || lower.contains("grow")
            || lower.contains("bloom") || lower.contains("fresh") {
            return "About hope, growth, and welcoming what is ahead."
        }

        if lower.contains("clarity") || lower.contains("clear") || lower.contains("simple")
            || lower.contains("priority") || lower.contains("plan") {
            return "About clarity, simplicity, and knowing what matters."
        }

        if lower.contains("joy") || lower.contains("delight") || lower.contains("laugh")
            || lower.contains("light") || lower.contains("spark") {
            return "About joy, lightness, and small moments of delight."
        }

        if lower.contains("rain") || lower.contains("weather") || lower.contains("sun") {
            return "About moving through the moment with ease and acceptance."
        }

        return "A gentle wish for a thoughtful, balanced path."
    }
}

enum DashboardDurationFormatting {
    static func analysisAgo(from date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes == 0 {
            return "just now"
        }
        if minutes == 1 {
            return "1 minute ago"
        }
        if minutes < 60 {
            return "\(minutes) minutes ago"
        }

        let hours = minutes / 60
        if hours == 1 {
            return "1 hour ago"
        }
        if hours < 24 {
            return "\(hours) hours ago"
        }

        let days = hours / 24
        if days == 1 {
            return "1 day ago"
        }
        return "\(days) days ago"
    }

    static func analysisUntil(_ date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 {
            return "due now"
        }
        if minutes == 1 {
            return "in 1 minute"
        }
        if minutes < 60 {
            return "in \(minutes) minutes"
        }

        let hours = Int(ceil(Double(minutes) / 60))
        if hours == 1 {
            return "in 1 hour"
        }
        return "in \(hours) hours"
    }
}
