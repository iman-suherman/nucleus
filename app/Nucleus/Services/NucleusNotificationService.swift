import CalendarKit
import Foundation
import NucleusKit
import UserNotifications

@MainActor
final class NucleusNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NucleusNotificationService()

    var onMailAction: ((MailNotificationAction) -> Void)?
    var onMeetingReminder: ((CalendarEventSummary, MeetingReminderPlanner.Reminder.Kind) -> Void)?

    enum MailNotificationAction {
        case open(messageID: String, accountID: UUID)
        case markRead(messageID: String, accountID: UUID)
        case quickReply(messageID: String, threadID: String, accountID: UUID, to: String, subject: String)
    }

    private override init() {
        super.init()
    }

    func prepare() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyNewMail(_ message: MailMessageSummary) {
        let content = UNMutableNotificationContent()
        content.title = "New Email"
        content.subtitle = message.fromName
        content.body = message.subject
        content.sound = Self.alertSound
        content.categoryIdentifier = "NUCLEUS_MAIL"
        content.userInfo = [
            "messageID": message.id,
            "threadID": message.threadID,
            "accountID": message.accountID.uuidString,
            "to": message.fromEmail,
            "subject": "Re: \(message.subject)",
        ]

        let request = UNNotificationRequest(
            identifier: "mail-\(message.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func notifyIncomingMail(unreadCount: Int, delta: Int, accountName: String) {
        let content = UNMutableNotificationContent()
        content.title = delta == 1 ? "New Email" : "\(delta) New Emails"
        content.subtitle = accountName
        content.body = unreadCount == 1 ? "1 unread message in your inbox" : "\(unreadCount) unread messages in your inbox"
        content.sound = Self.alertSound
        content.categoryIdentifier = "NUCLEUS_MAIL"

        let request = UNNotificationRequest(
            identifier: "mail-unread-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func notifyIncomingChat(unreadCount: Int, delta: Int, accountName: String) {
        let content = UNMutableNotificationContent()
        content.title = delta == 1 ? "New Chat Message" : "\(delta) New Chat Messages"
        content.subtitle = accountName
        content.body = unreadCount == 1 ? "1 unread message in Google Chat" : "\(unreadCount) unread messages in Google Chat"
        content.sound = Self.alertSound
        content.categoryIdentifier = "NUCLEUS_CHAT"

        let request = UNNotificationRequest(
            identifier: "chat-unread-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static let alertSound = UNNotificationSound(named: UNNotificationSoundName("Funky.caf"))

    func rescheduleMeetingReminders(_ reminders: [MeetingReminderPlanner.Reminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let calendarIDs = pending.filter { $0.identifier.hasPrefix("calendar-") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: calendarIDs)

        for reminder in reminders {
            let interval = reminder.fireDate.timeIntervalSinceNow
            guard interval > 0 else { continue }

            let content = meetingContent(for: reminder.event, kind: reminder.kind)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let identifier = "calendar-\(reminder.event.id)-\(reminder.kind.rawValue)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func notifyMeetingReminder(_ event: CalendarEventSummary, kind: MeetingReminderPlanner.Reminder.Kind) {
        let content = meetingContent(for: event, kind: kind)
        let request = UNNotificationRequest(
            identifier: "calendar-\(event.id)-\(kind.rawValue)-immediate",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func meetingContent(
        for event: CalendarEventSummary,
        kind: MeetingReminderPlanner.Reminder.Kind
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch kind {
        case .tenMinutes:
            content.title = "Meeting starts in 10 minutes"
            content.body = event.title
            content.categoryIdentifier = "NUCLEUS_MEETING"
        case .oneMinute:
            content.title = "Meeting starts in 1 minute"
            content.body = event.title
            content.categoryIdentifier = event.meetingLink == nil ? "NUCLEUS_MEETING" : "NUCLEUS_MEETING_JOIN"
        case .starting:
            content.title = "Meeting starting now"
            content.body = event.title
            content.categoryIdentifier = event.meetingLink == nil ? "NUCLEUS_MEETING" : "NUCLEUS_MEETING_JOIN"
        }
        content.sound = Self.alertSound
        content.userInfo = [
            "eventID": event.id,
            "eventTitle": event.title,
            "accountEmail": event.accountEmail,
            "meetingLink": event.meetingLink ?? "",
            "reminderKind": kind.rawValue,
        ]
        return content
    }

    func registerCategories() {
        let open = UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
        let markRead = UNNotificationAction(identifier: "MARK_READ", title: "Mark Read")
        let reply = UNNotificationAction(identifier: "QUICK_REPLY", title: "Reply", options: [.foreground])

        let mailCategory = UNNotificationCategory(
            identifier: "NUCLEUS_MAIL",
            actions: [open, markRead, reply],
            intentIdentifiers: []
        )
        let join = UNNotificationAction(identifier: "JOIN", title: "Join Meeting", options: [.foreground])
        let joinCategory = UNNotificationCategory(identifier: "NUCLEUS_MEETING_JOIN", actions: [join], intentIdentifiers: [])
        let meetingCategory = UNNotificationCategory(identifier: "NUCLEUS_MEETING", actions: [], intentIdentifiers: [])
        let chatCategory = UNNotificationCategory(identifier: "NUCLEUS_CHAT", actions: [open], intentIdentifiers: [])

        UNUserNotificationCenter.current().setNotificationCategories([mailCategory, joinCategory, meetingCategory, chatCategory])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await handleMeetingReminderPresentation(notification)
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run {
            switch response.actionIdentifier {
            case "OPEN":
                if let messageID = info["messageID"] as? String,
                   let accountIDRaw = info["accountID"] as? String,
                   let accountID = UUID(uuidString: accountIDRaw) {
                    onMailAction?(.open(messageID: messageID, accountID: accountID))
                }
            case "MARK_READ":
                if let messageID = info["messageID"] as? String,
                   let accountIDRaw = info["accountID"] as? String,
                   let accountID = UUID(uuidString: accountIDRaw) {
                    onMailAction?(.markRead(messageID: messageID, accountID: accountID))
                }
            case "QUICK_REPLY":
                if let messageID = info["messageID"] as? String,
                   let threadID = info["threadID"] as? String,
                   let accountIDRaw = info["accountID"] as? String,
                   let accountID = UUID(uuidString: accountIDRaw),
                   let to = info["to"] as? String,
                   let subject = info["subject"] as? String {
                    onMailAction?(.quickReply(
                        messageID: messageID,
                        threadID: threadID,
                        accountID: accountID,
                        to: to,
                        subject: subject
                    ))
                }
            case "JOIN":
                if let link = info["meetingLink"] as? String,
                   let url = URL(string: link) {
                    ChromeLauncher.open(url: url)
                }
            default:
                break
            }
        }
    }

    private func handleMeetingReminderPresentation(_ notification: UNNotification) async {
        guard notification.request.identifier.hasPrefix("calendar-") else { return }
        let info = notification.request.content.userInfo
        guard let title = info["eventTitle"] as? String,
              let accountEmail = info["accountEmail"] as? String else { return }

        onMeetingReminder?(
            CalendarEventSummary(
                id: info["eventID"] as? String ?? UUID().uuidString,
                accountID: UUID(),
                title: title,
                startDate: Date(),
                endDate: Date(),
                accountEmail: accountEmail
            ),
            MeetingReminderPlanner.Reminder.Kind(rawValue: info["reminderKind"] as? String ?? "") ?? .starting
        )
    }
}
