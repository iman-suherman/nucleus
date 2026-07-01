import CalendarKit
import Foundation
import NucleusKit

public enum MobileDashboardCalendarHelpers {
    public static let scheduleHorizonDays = 14
    public static let dashboardBirthdayHorizonDays = 7

    public static func todaysBirthdays(in events: [CalendarEventSummary], now: Date = Date()) -> [CalendarEventSummary] {
        let calendar = Calendar.current
        return events
            .filter { BirthdayCalendarFormatting.isBirthdayEvent($0) && calendar.isDateInToday($0.startDate) }
            .sorted { lhs, rhs in
                BirthdayCalendarFormatting.displayName(from: lhs.title)
                    .localizedCaseInsensitiveCompare(BirthdayCalendarFormatting.displayName(from: rhs.title)) == .orderedAscending
            }
    }

    public static func upcomingBirthdays(
        in events: [CalendarEventSummary],
        now: Date = Date(),
        withinDays: Int = scheduleHorizonDays
    ) -> [CalendarEventSummary] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: withinDays, to: now) ?? now
        return events
            .filter { event in
                BirthdayCalendarFormatting.isBirthdayEvent(event)
                    && event.startDate >= calendar.startOfDay(for: now)
                    && event.startDate <= horizon
            }
            .sorted { $0.startDate < $1.startDate }
    }

    /// All birthdays on the next upcoming birthday date (today if any, otherwise the nearest future date).
    public static func nextUpcomingBirthdays(
        in events: [CalendarEventSummary],
        now: Date = Date(),
        withinDays: Int = scheduleHorizonDays
    ) -> [CalendarEventSummary] {
        let upcoming = upcomingBirthdays(in: events, now: now, withinDays: withinDays)
        guard let nextDate = upcoming.first?.startDate else { return [] }

        let calendar = Calendar.current
        let nextDay = calendar.startOfDay(for: nextDate)
        return upcoming
            .filter { calendar.isDate($0.startDate, inSameDayAs: nextDay) }
            .sorted { lhs, rhs in
                BirthdayCalendarFormatting.displayName(from: lhs.title)
                    .localizedCaseInsensitiveCompare(BirthdayCalendarFormatting.displayName(from: rhs.title)) == .orderedAscending
            }
    }

    public static func upcomingScheduleEvents(
        in events: [CalendarEventSummary],
        now: Date = Date(),
        withinDays: Int = scheduleHorizonDays
    ) -> [CalendarEventSummary] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: withinDays, to: now) ?? now
        return events
            .filter { event in
                !BirthdayCalendarFormatting.isBirthdayEvent(event)
                    && event.endDate >= now
                    && event.startDate <= horizon
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                let emailOrder = lhs.accountEmail.localizedCaseInsensitiveCompare(rhs.accountEmail)
                if emailOrder != .orderedSame {
                    return emailOrder == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    public static func nextMeetingGroup(
        in events: [CalendarEventSummary],
        now: Date = Date()
    ) -> MeetingReminderPlanner.UpcomingMeetingGroup? {
        MeetingReminderPlanner.upcomingMeetingGroups(from: events, now: now).first
    }

    /// Count of distinct meeting start-time groups beginning within the next hour.
    public static func meetingsWithinHourBadgeCount(
        in events: [CalendarEventSummary],
        now: Date = Date(),
        within seconds: TimeInterval = 3600
    ) -> Int {
        let horizon = now.addingTimeInterval(seconds)
        let upcoming = events
            .filter { event in
                !BirthdayCalendarFormatting.isBirthdayEvent(event)
                    && event.startDate > now
                    && event.startDate <= horizon
            }
            .sorted { $0.startDate < $1.startDate }

        var seenGroupKeys: Set<String> = []
        var count = 0
        for event in upcoming {
            let groupKey = MeetingReminderPlanner.alertGroupKey(for: event, in: upcoming)
            guard seenGroupKeys.insert(groupKey).inserted else { continue }
            count += 1
        }
        return count
    }
}
