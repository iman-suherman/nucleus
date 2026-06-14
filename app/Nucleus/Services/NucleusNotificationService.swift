import CalendarKit
import Foundation
import NucleusKit
import UserNotifications

@MainActor
final class NucleusNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NucleusNotificationService()

    var onMailAction: ((MailNotificationAction) -> Void)?

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
        content.sound = .default
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

    func notifyMeetingReminder(_ event: CalendarEventSummary, kind: MeetingReminderPlanner.Reminder.Kind) {
        let content = UNMutableNotificationContent()
        switch kind {
        case .tenMinutes:
            content.title = "Meeting starts in 10 minutes"
            content.body = event.title
        case .oneMinute:
            content.title = "Meeting starts in 1 minute"
            content.body = event.title
        }
        content.sound = .default
        content.categoryIdentifier = kind == .oneMinute ? "NUCLEUS_MEETING_JOIN" : "NUCLEUS_MEETING"
        content.userInfo = [
            "eventID": event.id,
            "meetingLink": event.meetingLink ?? "",
        ]

        let request = UNNotificationRequest(
            identifier: "calendar-\(event.id)-\(kind.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func notifyClipboardSaved(_ entry: ClipboardEntry) {
        let content = UNMutableNotificationContent()
        content.title = "Clipboard Saved"
        content.body = String(entry.content.prefix(120))
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "clip-\(entry.id.uuidString)", content: content, trigger: nil)
        )
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

        UNUserNotificationCenter.current().setNotificationCategories([mailCategory, joinCategory, meetingCategory])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
}
