import AppKit
import Foundation
import NucleusKit
import UserNotifications

@MainActor
final class NucleusNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NucleusNotificationService()

    var onMailAction: ((MailNotificationAction) -> Void)?
    var onClipboardPasswordAction: ((ClipboardPasswordAction) -> Void)?

    enum ClipboardPasswordAction {
        case save(entryID: UUID)
        case dismiss(entryID: UUID)
        case show(entryID: UUID)
    }

    enum MailNotificationAction {
        case open(messageID: String, accountID: UUID)
        case markRead(messageID: String, accountID: UUID)
        case quickReply(messageID: String, threadID: String, accountID: UUID, to: String, subject: String)
    }

    private var passwordNotificationTimers: [UUID: Timer] = [:]
    private var pendingPasswordSuggestions: [UUID: ClipboardPasswordSuggestion] = [:]
    private var passwordNotificationHasPlayedSound: Set<UUID> = []

    /// How long the password notification stays visible before auto-dismiss.
    private let passwordNotificationDisplayDuration: TimeInterval = 45

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

    func notifyUnreadInboxMail(accountName: String, accountID: UUID) {
        guard AppSettings.shared.emailNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "New Email"
        content.subtitle = accountName
        content.body = "There's an unread message in your inbox."
        content.categoryIdentifier = "NUCLEUS_MAIL"
        content.userInfo = ["accountID": accountID.uuidString]

        postMailNotification(
            identifier: "mail-unread-\(accountID.uuidString)",
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

    func notifyClipboardPasswordSuggestion(_ suggestion: ClipboardPasswordSuggestion) {
        guard AppSettings.shared.clipboardPasswordDetectionEnabled else { return }
        guard !isAppActive else { return }
        guard pendingPasswordSuggestions[suggestion.id] == nil else { return }
        guard !pendingPasswordSuggestions.values.contains(where: { $0.password == suggestion.password }) else { return }

        pendingPasswordSuggestions[suggestion.id] = suggestion
        postPasswordNotification(suggestion, playSound: !passwordNotificationHasPlayedSound.contains(suggestion.id))
        passwordNotificationHasPlayedSound.insert(suggestion.id)
        schedulePasswordNotificationAutoDismiss(for: suggestion.id)
    }

    func clearPasswordNotification(entryID: UUID) {
        passwordNotificationTimers[entryID]?.invalidate()
        passwordNotificationTimers.removeValue(forKey: entryID)
        pendingPasswordSuggestions.removeValue(forKey: entryID)
        passwordNotificationHasPlayedSound.remove(entryID)

        let identifier = passwordNotificationIdentifier(for: entryID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func passwordNotificationIdentifier(for entryID: UUID) -> String {
        "clipboard-password-\(entryID.uuidString)"
    }

    private func postPasswordNotification(_ suggestion: ClipboardPasswordSuggestion, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Password detected on clipboard"
        content.subtitle = suggestion.sourceApplication
        content.body = "Nucleus noticed a password-like value. Save it to Passwords?"
        content.categoryIdentifier = "NUCLEUS_CLIPBOARD_PASSWORD"
        content.interruptionLevel = .timeSensitive
        content.sound = playSound ? .default : nil
        content.userInfo = [
            "entryID": suggestion.id.uuidString,
        ]

        let request = UNNotificationRequest(
            identifier: passwordNotificationIdentifier(for: suggestion.id),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func schedulePasswordNotificationAutoDismiss(for entryID: UUID) {
        passwordNotificationTimers[entryID]?.invalidate()
        passwordNotificationTimers[entryID] = Timer.scheduledTimer(
            withTimeInterval: passwordNotificationDisplayDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearPasswordNotification(entryID: entryID)
            }
        }
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

    /// Removes legacy macOS meeting notifications. Meeting alerts are shown in-app only.
    func clearMeetingReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let calendarIDs = pending.filter { $0.identifier.hasPrefix("calendar-") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: calendarIDs)

        let delivered = await center.deliveredNotifications()
        let deliveredCalendarIDs = delivered
            .filter { $0.request.identifier.hasPrefix("calendar-") }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: deliveredCalendarIDs)
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

    func registerCategories() {
        let open = UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
        let markRead = UNNotificationAction(identifier: "MARK_READ", title: "Mark Read")
        let reply = UNNotificationAction(identifier: "QUICK_REPLY", title: "Reply", options: [.foreground])

        let mailCategory = UNNotificationCategory(
            identifier: "NUCLEUS_MAIL",
            actions: [open, markRead, reply],
            intentIdentifiers: []
        )
        let chatCategory = UNNotificationCategory(identifier: "NUCLEUS_CHAT", actions: [open], intentIdentifiers: [])
        let billCategory = UNNotificationCategory(identifier: "NUCLEUS_BILL", actions: [open], intentIdentifiers: [])
        let savePassword = UNNotificationAction(
            identifier: "SAVE_PASSWORD",
            title: "Save to Passwords",
            options: []
        )
        let dismissPassword = UNNotificationAction(identifier: "DISMISS_PASSWORD", title: "Not Now")
        let clipboardPasswordCategory = UNNotificationCategory(
            identifier: "NUCLEUS_CLIPBOARD_PASSWORD",
            actions: [savePassword, dismissPassword],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            mailCategory, chatCategory, billCategory, clipboardPasswordCategory,
        ])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await foregroundPresentationOptions(for: notification)
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
        case "NUCLEUS_CLIPBOARD_PASSWORD":
            return [.banner, .list, .sound]
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
            case "SAVE_PASSWORD":
                if let entryIDRaw = info["entryID"] as? String,
                   let entryID = UUID(uuidString: entryIDRaw) {
                    clearPasswordNotification(entryID: entryID)
                    onClipboardPasswordAction?(.show(entryID: entryID))
                }
            case "DISMISS_PASSWORD":
                if let entryIDRaw = info["entryID"] as? String,
                   let entryID = UUID(uuidString: entryIDRaw) {
                    clearPasswordNotification(entryID: entryID)
                    onClipboardPasswordAction?(.dismiss(entryID: entryID))
                }
            default:
                if response.notification.request.identifier.hasPrefix("clipboard-password-"),
                   let entryIDRaw = info["entryID"] as? String,
                   let entryID = UUID(uuidString: entryIDRaw) {
                    clearPasswordNotification(entryID: entryID)
                    onClipboardPasswordAction?(.show(entryID: entryID))
                } else if response.notification.request.identifier.hasPrefix("bill-"),
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
}
