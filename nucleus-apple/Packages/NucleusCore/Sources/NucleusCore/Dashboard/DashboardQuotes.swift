import Foundation

public enum DashboardQuotes {
    public static let storageKey = "nucleus.dashboard.quote"
    public static let contextKey = "nucleus.dashboard.quote.context"

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

    public struct Context: Equatable, Sendable {
        public let schedule: DashboardQuoteSchedule
        public let period: DashboardTimePeriod

        public var storageToken: String {
            "\(schedule.rawValue).\(period.rawValue)"
        }

        public static func current(
            now: Date = Date(),
            calendar: Calendar = .current,
            isPublicHoliday: Bool = false
        ) -> Context {
            let schedule: DashboardQuoteSchedule
            if DashboardGreeting.isWeekend(now: now, calendar: calendar) || isPublicHoliday {
                schedule = .leisure
            } else {
                schedule = .weekday
            }
            return Context(
                schedule: schedule,
                period: DashboardTimePeriod.current(now: now, calendar: calendar)
            )
        }
    }

    private static let library: QuoteLibrary = {
        if let url = Bundle.module.url(forResource: "DashboardQuotes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(QuoteLibrary.self, from: data) {
            return decoded
        }
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
    }()

    private static let fallbackQuote = "May your path be calm, focused, and full of small wins."

    public static func currentOrRandom(isPublicHoliday: Bool = false) -> String {
        let context = Context.current(isPublicHoliday: isPublicHoliday)
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           UserDefaults.standard.string(forKey: contextKey) == context.storageToken,
           quotes(for: context).contains(saved) {
            return saved
        }
        return pickRandom(excluding: nil, context: context)
    }

    @discardableResult
    public static func refreshIfContextChanged(
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

    public static func pickRandom(
        excluding current: String? = nil,
        isPublicHoliday: Bool = false
    ) -> String {
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

    public static func quoteBody(from quote: String) -> String {
        var text = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        while text.hasSuffix(".") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    public static func displayBody(from quote: String, emojis: String) -> String {
        let body = quoteBody(from: quote)
        let trimmedEmojis = emojis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmojis.isEmpty else { return body }
        return "\(body) \(trimmedEmojis) "
    }
}
