import AppKit
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

    func notifyNewMail(_ message: MailMessageSummary, accountName: String? = nil) {
        guard AppSettings.shared.emailNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        let sender = message.fromName.isEmpty ? message.fromEmail : message.fromName
        content.title = sender
        content.subtitle = accountName ?? message.subject
        if accountName == nil {
            content.body = message.subject
        } else if message.snippet.isEmpty || message.snippet == message.subject {
            content.body = message.subject
        } else {
            content.body = "\(message.subject)\n\(message.snippet)"
        }
        content.categoryIdentifier = "NUCLEUS_MAIL"
        content.userInfo = [
            "messageID": message.id,
            "threadID": message.threadID,
            "accountID": message.accountID.uuidString,
            "to": message.fromEmail,
            "subject": "Re: \(message.subject)",
        ]

        postMailNotification(
            identifier: "mail-\(message.id)",
            content: content,
            accountID: message.accountID
        )
    }

    func notifyNewMailMessages(_ messages: [MailMessageSummary], accountName: String) {
        for message in messages {
            notifyNewMail(message, accountName: accountName)
        }
    }

    func notifyIncomingMail(unreadCount: Int, delta: Int, accountName: String, accountID: UUID) {
        guard AppSettings.shared.emailNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = delta == 1 ? "New Email" : "\(delta) New Emails"
        content.subtitle = accountName
        content.body = unreadCount == 1 ? "1 unread message in your inbox" : "\(unreadCount) unread messages in your inbox"
        content.categoryIdentifier = "NUCLEUS_MAIL"
        content.userInfo = ["accountID": accountID.uuidString]

        postMailNotification(
            identifier: "mail-unread-\(UUID().uuidString)",
            content: content,
            accountID: accountID
        )
    }

    func notifyIncomingChat(unreadCount: Int, delta: Int, accountName: String, accountID: UUID) {
        guard AppSettings.shared.chatNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = delta == 1 ? "New Chat Message" : "\(delta) New Chat Messages"
        content.subtitle = accountName
        if delta == 1 {
            content.body = unreadCount == 1
                ? "You have 1 unread message in Google Chat for \(accountName)."
                : "New message in Google Chat for \(accountName). \(unreadCount) unread messages waiting."
        } else {
            content.body = "\(delta) new messages in Google Chat for \(accountName). \(unreadCount) unread messages waiting."
        }
        content.categoryIdentifier = "NUCLEUS_CHAT"
        content.userInfo = ["accountID": accountID.uuidString]

        postChatNotification(
            identifier: "chat-unread-\(UUID().uuidString)",
            content: content,
            accountID: accountID
        )
    }

    private func postChatNotification(
        identifier: String,
        content: UNMutableNotificationContent,
        accountID: UUID
    ) {
        content.sound = nil
        let sound = AppSettings.shared.chatNotificationSound(for: accountID)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isAppActive, sound != .silent else { return }
                sound.playAlert()
            }
        }
    }

    private func chatSound(for notification: UNNotification) -> ChatNotificationSound {
        guard let accountID = accountID(from: notification) else {
            return AppSettings.shared.chatNotificationSound
        }
        return AppSettings.shared.chatNotificationSound(for: accountID)
    }

    private var isAppActive: Bool {
        NSApplication.shared.isActive
    }

    private func postMailNotification(
        identifier: String,
        content: UNMutableNotificationContent,
        accountID: UUID
    ) {
        content.sound = nil
        let sound = AppSettings.shared.mailNotificationSound(for: accountID)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isAppActive, sound != .silent else { return }
                sound.playAlert()
            }
        }
    }

    private func mailSound(for notification: UNNotification) -> MailNotificationSound {
        guard let accountID = accountID(from: notification) else {
            return AppSettings.shared.mailNotificationSound
        }
        return AppSettings.shared.mailNotificationSound(for: accountID)
    }

    private func accountID(from notification: UNNotification) -> UUID? {
        guard let raw = notification.request.content.userInfo["accountID"] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    func rescheduleMeetingReminders(_ reminders: [MeetingReminderPlanner.Reminder]) async {
        guard AppSettings.shared.calendarNotificationsEnabled else { return }
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

    func rescheduleBillReminders(
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
        content.categoryIdentifier = "NUCLEUS_BILL"
        content.sound = .default
        content.userInfo = [
            "billID": reminder.bill.id.uuidString,
            "reminderKind": reminder.kind.rawValue,
        ]
        return content
    }

    func notifyMeetingReminder(_ event: CalendarEventSummary, kind: MeetingReminderPlanner.Reminder.Kind) {
        guard AppSettings.shared.calendarNotificationsEnabled else { return }
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
        content.sound = Self.meetingSound
        content.userInfo = [
            "eventID": event.id,
            "eventTitle": event.title,
            "accountEmail": event.accountEmail,
            "meetingLink": event.meetingLink ?? "",
            "reminderKind": kind.rawValue,
        ]
        return content
    }

    private static let meetingSound = UNNotificationSound(named: UNNotificationSoundName("Funky"))

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
        let billCategory = UNNotificationCategory(identifier: "NUCLEUS_BILL", actions: [open], intentIdentifiers: [])

        UNUserNotificationCenter.current().setNotificationCategories([
            mailCategory, joinCategory, meetingCategory, chatCategory, billCategory,
        ])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let options = await foregroundPresentationOptions(for: notification)
        await handleMeetingReminderPresentation(notification)
        return options
    }

    private func foregroundPresentationOptions(for notification: UNNotification) -> UNNotificationPresentationOptions {
        switch notification.request.content.categoryIdentifier {
        case "NUCLEUS_MAIL":
            let sound = mailSound(for: notification)
            guard sound != .silent else { return [.banner] }
            sound.playAlert()
            return [.banner]
        case "NUCLEUS_CHAT":
            let sound = chatSound(for: notification)
            guard sound != .silent else { return [.banner] }
            sound.playAlert()
            return [.banner]
        default:
            return [.banner, .sound]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run {
            switch response.actionIdentifier {
            case "OPEN":
                if response.notification.request.identifier.hasPrefix("bill-"),
                   let billIDRaw = info["billID"] as? String,
                   let billID = UUID(uuidString: billIDRaw) {
                    AppSettings.shared.selectedWorkspacePane = WorkspacePane.bills.rawValue
                    AppViewModel.current?.sidebarSelection = .workspace(.bills)
                    AppViewModel.current?.selectedBillID = billID
                } else if let messageID = info["messageID"] as? String,
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
                if response.notification.request.identifier.hasPrefix("bill-"),
                   let billIDRaw = info["billID"] as? String,
                   let billID = UUID(uuidString: billIDRaw) {
                    AppSettings.shared.selectedWorkspacePane = WorkspacePane.bills.rawValue
                    AppViewModel.current?.sidebarSelection = .workspace(.bills)
                    AppViewModel.current?.selectedBillID = billID
                }
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
