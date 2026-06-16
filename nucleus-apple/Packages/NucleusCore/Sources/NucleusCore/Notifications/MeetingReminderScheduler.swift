import Foundation
import NucleusKit
import UserNotifications

/// Phase 2: Local meeting reminders (10 min and 1 min before) with join-meeting action.
@MainActor
public final class MeetingReminderScheduler {
    public static let shared = MeetingReminderScheduler()

    public static let joinMeetingCategoryID = "NUCLEUS_JOIN_MEETING"
    public static let joinMeetingActionID = "JOIN_MEETING"

    private init() {}

    public func registerCategories() {
        let joinAction = UNNotificationAction(
            identifier: Self.joinMeetingActionID,
            title: "Join meeting",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.joinMeetingCategoryID,
            actions: [joinAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    public func scheduleReminders(for event: CalendarEventSummary) async {
        guard event.startDate > Date() else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        center.removePendingNotificationRequests(withIdentifiers: notificationIDs(for: event.id))

        for (minutes, suffix) in [(10, "10min"), (1, "1min")] {
            let fireDate = event.startDate.addingTimeInterval(-TimeInterval(minutes * 60))
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = minutes == 1
                ? "Starting in 1 minute"
                : "Starting in 10 minutes"
            content.sound = .default
            content.categoryIdentifier = Self.joinMeetingCategoryID
            if let link = event.meetingLink {
                content.userInfo = ["meetingLink": link]
            }

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(event.id)-\(suffix)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    public func cancelReminders(for eventID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: notificationIDs(for: eventID)
        )
    }

    private func notificationIDs(for eventID: String) -> [String] {
        ["\(eventID)-10min", "\(eventID)-1min"]
    }
}
