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

    var rawValue: String {
        switch self {
        case .morning: return "morning"
        case .afternoon: return "afternoon"
        case .evening: return "evening"
        case .night: return "night"
        }
    }
}

enum DashboardWeekday: String, CaseIterable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
    case holiday

    static func current(
        now: Date = Date(),
        calendar: Calendar = .current,
        isPublicHoliday: Bool = false
    ) -> DashboardWeekday {
        if isPublicHoliday && !DashboardGreeting.isWeekend(now: now, calendar: calendar) {
            return .holiday
        }

        switch calendar.component(.weekday, from: now) {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .sunday
        }
    }
}

enum DashboardQuotes {
    static let storageKey = "nucleus.dashboard.quote"
    static let contextKey = "nucleus.dashboard.quote.context"

    struct Context: Equatable {
        let weekday: DashboardWeekday
        let period: DashboardTimePeriod

        var storageToken: String {
            "\(weekday.rawValue).\(period.rawValue)"
        }

        static func current(isPublicHoliday: Bool = false) -> Context {
            Context(
                weekday: DashboardWeekday.current(isPublicHoliday: isPublicHoliday),
                period: DashboardTimePeriod.current()
            )
        }
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

    private struct QuoteLibrary: Decodable {
        let monday: PeriodQuotes
        let tuesday: PeriodQuotes
        let wednesday: PeriodQuotes
        let thursday: PeriodQuotes
        let friday: PeriodQuotes
        let saturday: PeriodQuotes
        let sunday: PeriodQuotes
        let holiday: PeriodQuotes

        func quotes(for weekday: DashboardWeekday, period: DashboardTimePeriod) -> [String] {
            switch weekday {
            case .monday: return monday.quotes(for: period)
            case .tuesday: return tuesday.quotes(for: period)
            case .wednesday: return wednesday.quotes(for: period)
            case .thursday: return thursday.quotes(for: period)
            case .friday: return friday.quotes(for: period)
            case .saturday: return saturday.quotes(for: period)
            case .sunday: return sunday.quotes(for: period)
            case .holiday: return holiday.quotes(for: period)
            }
        }
    }

    private static let library: QuoteLibrary = {
        guard let url = Bundle.main.url(forResource: "DashboardQuotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(QuoteLibrary.self, from: data)
        else {
            return fallbackLibrary
        }
        return decoded
    }()

    private static let fallbackLibrary = QuoteLibrary(
        monday: fallbackPeriodQuotes,
        tuesday: fallbackPeriodQuotes,
        wednesday: fallbackPeriodQuotes,
        thursday: fallbackPeriodQuotes,
        friday: fallbackPeriodQuotes,
        saturday: fallbackPeriodQuotes,
        sunday: fallbackPeriodQuotes,
        holiday: fallbackPeriodQuotes
    )

    private static let fallbackPeriodQuotes = PeriodQuotes(
        morning: [fallbackQuote],
        afternoon: [fallbackQuote],
        evening: [fallbackQuote],
        night: [fallbackQuote]
    )

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
        library.quotes(for: context.weekday, period: context.period)
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
