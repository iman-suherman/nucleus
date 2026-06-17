import Foundation
import NucleusKit
import UserNotifications

@MainActor
public final class MobileBillReminderScheduler {
    public static let shared = MobileBillReminderScheduler()

    private init() {}

    public func rescheduleBillReminders(
        bills: [Bill],
        payments: [BillPayment],
        configuration: BillDueReminderConfiguration
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let billIDs = pending.filter { $0.identifier.hasPrefix("bill-") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: billIDs)

        guard configuration.enabled else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let reminders = BillDueReminderPlanner.reminders(
            bills: bills,
            payments: payments,
            configuration: configuration
        )

        for reminder in reminders {
            let content = billReminderContent(for: reminder)
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reminder.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = BillDueReminderPlanner.notificationIdentifier(for: reminder)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private func billReminderContent(for reminder: BillDueReminderPlanner.Reminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = BillDueReminderPlanner.notificationTitle(for: reminder)
        content.body = BillDueReminderPlanner.notificationBody(for: reminder)
        content.sound = .default
        content.userInfo = [
            "billID": reminder.bill.id.uuidString,
            "reminderKind": reminder.kind.rawValue,
        ]
        return content
    }
}
