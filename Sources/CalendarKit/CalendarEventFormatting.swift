import Foundation
import NucleusKit

public enum CalendarEventFormatting {
    public static func shortTime(for date: Date) -> String {
        shortTimeFormatter.string(from: date)
    }

    public static func timeRangeLabel(for event: CalendarEventSummary) -> String {
        "\(shortTime(for: event.startDate)) – \(shortTime(for: event.endDate))"
    }

    public static func durationMinutes(for event: CalendarEventSummary) -> Int {
        let seconds = max(0, event.endDate.timeIntervalSince(event.startDate))
        return max(1, Int((seconds / 60).rounded()))
    }

    public static func durationLabel(for event: CalendarEventSummary) -> String {
        let minutes = durationMinutes(for: event)
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return hours == 1 ? "1 hr" : "\(hours) hr"
        }
        let hourLabel = hours == 1 ? "1 hr" : "\(hours) hr"
        return "\(hourLabel) \(remainder) min"
    }

    public static func scheduleTimeAndDurationLabel(for event: CalendarEventSummary) -> String {
        "\(timeRangeLabel(for: event)) · \(durationLabel(for: event))"
    }

    public static func timeUntilStartMinutes(for startDate: Date, now: Date = Date()) -> Int {
        max(0, Int((startDate.timeIntervalSince(now) / 60).rounded()))
    }

    public static func timeUntilStartLabel(for startDate: Date, now: Date = Date()) -> String {
        let minutes = timeUntilStartMinutes(for: startDate, now: now)
        if minutes <= 0 {
            return "starting now"
        }
        if minutes < 60 {
            return minutes == 1 ? "in 1 min" : "in \(minutes) min"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return hours == 1 ? "in 1 hr" : "in \(hours) hr"
        }
        let hourLabel = hours == 1 ? "in 1 hr" : "in \(hours) hr"
        return "\(hourLabel) \(remainder) min"
    }

    public static func timeUntilStartWithDurationLabel(
        for event: CalendarEventSummary,
        now: Date = Date()
    ) -> String {
        let countdown = timeUntilStartLabel(for: event.startDate, now: now)
        let duration = durationLabel(for: event)
        if countdown == "starting now" {
            return "starting now for \(duration)"
        }
        return "\(countdown) for \(duration)"
    }

    public static func meetingStartsInLabel(for startDate: Date, now: Date = Date()) -> String {
        let until = timeUntilStartLabel(for: startDate, now: now)
        if until == "starting now" {
            return "Meeting starting now"
        }
        return "Meeting \(until)"
    }

    public static func nextMeetingNotificationLabel(
        for event: CalendarEventSummary,
        now: Date = Date()
    ) -> String {
        let countdown = timeUntilStartLabel(for: event.startDate, now: now)
        return "\(countdown) · \(scheduleTimeAndDurationLabel(for: event))"
    }

    public static func nextMeetingDayPrefix(for startDate: Date, now: Date = Date()) -> String? {
        let calendar = Calendar.current
        if calendar.isDateInToday(startDate) {
            return nil
        }
        if calendar.isDateInTomorrow(startDate) {
            return "Tomorrow"
        }
        return dayFormatter.string(from: startDate)
    }

    public static func nextMeetingScheduleLabel(
        for event: CalendarEventSummary,
        now: Date = Date()
    ) -> String {
        nextMeetingNotificationLabel(for: event, now: now)
    }

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()
}
