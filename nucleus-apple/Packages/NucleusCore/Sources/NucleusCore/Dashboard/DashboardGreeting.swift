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

public enum DashboardWeekday: String, CaseIterable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
    case holiday

    public static func current(
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
