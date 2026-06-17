import Foundation

public enum DashboardTimePeriod: String, CaseIterable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    public static func current(now: Date = Date(), calendar: Calendar = .current) -> DashboardTimePeriod {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }
}

public enum DashboardQuoteSchedule: String, Sendable {
    case weekday
    case leisure
}

public enum DashboardGreeting {
    public static func firstName(from fullName: String?) -> String {
        let trimmed = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let first = trimmed.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        return trimmed.isEmpty ? "there" : trimmed
    }

    public static func timeOfDay(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        timeOfDay(for: .current(now: now, calendar: calendar))
    }

    public static func timeOfDay(for period: DashboardTimePeriod) -> String {
        switch period {
        case .morning: return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening: return "Good evening"
        case .night: return "Good night"
        }
    }

    public static func isWeekend(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.isDateInWeekend(now)
    }
}
