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
        UNUserNotificationCenter.current().add(request) { _ in
            Task { @MainActor in
                MeetingNotificationSound.playAlert()
            }
        }
    }

    private func meetingContent(
        for event: CalendarEventSummary,
        kind: MeetingReminderPlanner.Reminder.Kind
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Meeting in 2 minutes"
        content.body = event.title
        content.categoryIdentifier = event.meetingLink == nil ? "NUCLEUS_MEETING" : "NUCLEUS_MEETING_JOIN"
        content.sound = MeetingNotificationSound.notificationSound
        content.userInfo = meetingUserInfo(for: event, kind: kind)
        return content
    }

    private func meetingUserInfo(
        for event: CalendarEventSummary,
        kind: MeetingReminderPlanner.Reminder.Kind
    ) -> [String: Any] {
        var info: [String: Any] = [
            "eventID": event.id,
            "eventTitle": event.title,
            "accountEmail": event.accountEmail,
            "accountID": event.accountID.uuidString,
            "startDate": event.startDate.timeIntervalSince1970,
            "endDate": event.endDate.timeIntervalSince1970,
            "location": event.location,
            "reminderKind": kind.rawValue,
        ]
        if let meetingLink = event.meetingLink {
            info["meetingLink"] = meetingLink
        }
        return info
    }

    private func eventSummary(from info: [AnyHashable: Any]) -> CalendarEventSummary? {
        guard let id = info["eventID"] as? String,
              let title = info["eventTitle"] as? String,
              let accountEmail = info["accountEmail"] as? String,
              let startInterval = info["startDate"] as? TimeInterval,
              let endInterval = info["endDate"] as? TimeInterval else {
            return nil
        }

        let accountID = (info["accountID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let location = info["location"] as? String ?? ""
        let meetingLink = info["meetingLink"] as? String

        return CalendarEventSummary(
            id: id,
            accountID: accountID,
            title: title,
            startDate: Date(timeIntervalSince1970: startInterval),
            endDate: Date(timeIntervalSince1970: endInterval),
            location: location,
            meetingLink: meetingLink,
            accountEmail: accountEmail
        )
    }

    private func isMeetingNotification(_ notification: UNNotification) -> Bool {
        notification.request.identifier.hasPrefix("calendar-")
            || notification.request.content.categoryIdentifier == "NUCLEUS_MEETING"
            || notification.request.content.categoryIdentifier == "NUCLEUS_MEETING_JOIN"
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
            mailCategory, joinCategory, meetingCategory, chatCategory, billCategory, clipboardPasswordCategory,
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
        case "NUCLEUS_CLIPBOARD_PASSWORD":
            return [.banner, .list, .sound]
        case "NUCLEUS_MEETING", "NUCLEUS_MEETING_JOIN":
            return []
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
                    AppViewModel.current?.dismissMeetingReminder()
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
                if isMeetingNotification(response.notification),
                   let event = eventSummary(from: info) {
                    AppViewModel.current?.presentMeetingReminder(
                        event,
                        kind: MeetingReminderPlanner.Reminder.Kind(
                            rawValue: info["reminderKind"] as? String ?? ""
                        ) ?? .twoMinutes
                    )
                } else if response.notification.request.identifier.hasPrefix("clipboard-password-"),
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

    private func handleMeetingReminderPresentation(_ notification: UNNotification) async {
        guard isMeetingNotification(notification) else { return }
        let info = notification.request.content.userInfo
        guard let event = eventSummary(from: info) else { return }

        onMeetingReminder?(
            event,
            MeetingReminderPlanner.Reminder.Kind(rawValue: info["reminderKind"] as? String ?? "") ?? .twoMinutes
        )
    }
}
