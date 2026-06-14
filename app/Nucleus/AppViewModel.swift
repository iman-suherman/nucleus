import AccountKit
import CalendarKit
import ClipboardKit
import Combine
import DatabaseKit
import Foundation
import MailKit
import NotesKit
import NucleusKit
import SwiftData
import SwiftUI

enum SidebarSelection: Hashable {
    case workspace(WorkspacePane)
}

struct QuickReplyContext: Identifiable {
    let id = UUID()
    var messageID: String
    var threadID: String
    var accountID: UUID
    var to: String
    var subject: String
}

@MainActor
final class AppViewModel: ObservableObject {
    static weak var current: AppViewModel?

    @Published var sidebarSelection: SidebarSelection = .workspace(.inbox)
    @Published var accounts: [GoogleAccount] = []
    @Published var clipboardEntries: [ClipboardEntry] = []
    @Published var calendarEvents: [CalendarEventSummary] = []
    @Published var activityFeed: [ActivityItem] = []
    @Published var notes: [NoteDocument] = []
    @Published var mailMessages: [MailMessageSummary] = []
    @Published var unreadByAccount: [UUID: Int] = [:]
    @Published var totalUnread = 0
    @Published var clipboardSearchQuery = ""
    @Published var selectedNoteID: UUID?
    @Published var isStartingUp = true
    @Published var startupMessage = "Preparing workspace…"
    @Published var startupCompletedSteps: Set<StartupStep> = []
    @Published var startupActiveStep: StartupStep?
    @Published var startupProgressFraction: Double = 0
    @Published var statusMessage = "Ready"
    @Published var quickReplyContext: QuickReplyContext?
    @Published var oauthError: String?

    let modelContainer: ModelContainer
    private let mailSyncService = MailSyncService()
    private let calendarSyncService = CalendarSyncService()
    private var knownMessageIDs = Set<String>()
    private var scheduledReminderKeys = Set<String>()

    init() {
        modelContainer = (try? NucleusDatabase.makeContainer()) ?? {
            fatalError("Failed to create Nucleus database container")
        }()
        AppViewModel.current = self
    }

    func bootstrap(settings: AppSettings) async {
        isStartingUp = true
        startupCompletedSteps = []
        startupActiveStep = nil
        startupProgressFraction = 0

        await beginStartupStep(.database, message: "Loading workspace data…")
        reloadLocalData()
        completeStartupStep(.database)

        await beginStartupStep(.accounts, message: "Restoring Google accounts…")
        await AccountSessionStore.shared.updateConfiguration(
            settings.oauthConfiguration,
            clientSecret: settings.googleClientSecret.nilIfEmpty
        )
        completeStartupStep(.accounts)

        await beginStartupStep(.clipboard, message: "Starting clipboard monitor…")
        ClipboardMonitorService.shared.onCapture = { [weak self] capture in
            Task { @MainActor in
                self?.handleClipboardCapture(capture)
            }
        }
        ClipboardMonitorService.shared.start()
        completeStartupStep(.clipboard)

        await beginStartupStep(.notifications, message: "Preparing notifications…")
        NucleusNotificationService.shared.prepare()
        NucleusNotificationService.shared.registerCategories()
        NucleusNotificationService.shared.onMailAction = { [weak self] action in
            Task { @MainActor in
                self?.handleMailNotificationAction(action)
            }
        }
        completeStartupStep(.notifications)

        await beginStartupStep(.mailSync, message: "Syncing mail…")
        mailSyncService.start(viewModel: self, interval: settings.mailSyncInterval)
        await syncMail()
        completeStartupStep(.mailSync)

        await beginStartupStep(.calendarSync, message: "Syncing calendar…")
        calendarSyncService.start(viewModel: self, interval: settings.calendarSyncInterval)
        await syncCalendar()
        completeStartupStep(.calendarSync)

        if accounts.isEmpty {
            seedDemoDataIfNeeded()
        }

        DockBadgeController.update(unreadCount: totalUnread)
        startupMessage = "Nucleus is ready"
        startupProgressFraction = 1
        try? await Task.sleep(nanoseconds: 250_000_000)
        isStartingUp = false
        statusMessage = statusMessageForCurrentState()
    }

    func checkForUpdatesWhenEligible() {
        SparkleUpdaterController.shared.checkForUpdatesInForegroundIfNeeded()
    }

    private func statusMessageForCurrentState() -> String {
        if accounts.isEmpty {
            return "Add a Google account to begin"
        }
        if totalUnread > 0 {
            return "\(totalUnread) unread messages"
        }
        if calendarEvents.isEmpty {
            return "No upcoming events"
        }
        return "\(calendarEvents.count) upcoming events"
    }

    private func beginStartupStep(_ step: StartupStep, message: String) async {
        startupActiveStep = step
        startupMessage = message
        refreshStartupProgress()
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    private func completeStartupStep(_ step: StartupStep) {
        startupCompletedSteps.insert(step)
        if startupActiveStep == step {
            startupActiveStep = nil
        }
        refreshStartupProgress()
    }

    private func refreshStartupProgress() {
        let total = Double(StartupStep.allCases.count)
        let completed = Double(startupCompletedSteps.count)
        let activeBonus = startupActiveStep == nil ? 0 : 0.35
        startupProgressFraction = min(1, (completed + activeBonus) / total)
    }

    func reloadLocalData() {
        let context = ModelContext(modelContainer)
        accounts = (try? AccountRepository.fetchAll(context: context)) ?? []
        clipboardEntries = (try? ClipboardRepository.fetchRecent(context: context)) ?? []
        calendarEvents = (try? CalendarRepository.fetchUpcoming(context: context)) ?? []
        activityFeed = (try? ActivityRepository.fetchRecent(context: context)) ?? []
        notes = (try? NoteRepository.fetchAll(context: context)) ?? []
        totalUnread = (try? MailRepository.unreadCount(context: context)) ?? 0

        if selectedNoteID == nil {
            selectedNoteID = notes.first?.id
        }
        if let primary = accounts.first(where: { $0.isPrimary }) ?? accounts.first {
            AppSettings.shared.selectedMailAccountID = primary.id
        }
    }

    func addGoogleAccount(settings: AppSettings) async {
        oauthError = nil
        guard settings.oauthConfiguration.isConfigured else {
            oauthError = "Enter your Google OAuth Client ID in Settings first."
            sidebarSelection = .workspace(.accounts)
            return
        }

        do {
            let (tokens, profile) = try await GoogleOAuthCoordinator.shared.signIn(
                configuration: settings.oauthConfiguration,
                clientSecret: settings.googleClientSecret.nilIfEmpty
            )

            let account = GoogleAccount(
                email: profile.email,
                displayName: profile.name,
                avatarURL: profile.picture ?? "",
                isPrimary: accounts.isEmpty,
                isPrimaryNotesAccount: accounts.isEmpty
            )

            try KeychainTokenStore.shared.saveTokens(tokens, accountID: account.id)

            let context = ModelContext(modelContainer)
            try AccountRepository.upsert(account, context: context)
            reloadLocalData()
            await syncMail()
            await syncCalendar()

            try appendActivity(
                ActivityItem(
                    title: "Account connected",
                    detail: profile.email,
                    source: .gmail
                )
            )
            statusMessage = "Connected \(profile.email)"
        } catch {
            oauthError = error.localizedDescription
            statusMessage = "Sign-in failed"
        }
    }

    func removeAccount(_ account: GoogleAccount) {
        KeychainTokenStore.shared.deleteTokens(accountID: account.id)
        let context = ModelContext(modelContainer)
        try? AccountRepository.delete(id: account.id, context: context)
        reloadLocalData()
    }

    func setPrimaryAccount(_ account: GoogleAccount) {
        let context = ModelContext(modelContainer)
        try? AccountRepository.setPrimary(id: account.id, context: context)
        AppSettings.shared.selectedMailAccountID = account.id
        reloadLocalData()
    }

    func setPrimaryNotesAccount(_ account: GoogleAccount) {
        let context = ModelContext(modelContainer)
        try? AccountRepository.setPrimaryNotesAccount(id: account.id, context: context)
        reloadLocalData()
    }

    func syncMail() async {
        guard !accounts.isEmpty else {
            totalUnread = 0
            DockBadgeController.update(unreadCount: 0)
            return
        }

        statusMessage = "Syncing mail…"
        let result = await MailSyncEngine.sync(
            accounts: accounts,
            knownMessageIDs: knownMessageIDs,
            accessTokenProvider: { accountID in
                try await AccountSessionStore.shared.validAccessToken(accountID: accountID)
            }
        )

        unreadByAccount = result.unreadByAccount
        totalUnread = result.totalUnread
        mailMessages = result.messages
        knownMessageIDs.formUnion(result.messages.map(\.id))

        let context = ModelContext(modelContainer)
        try? MailRepository.replaceMessages(result.messages, context: context)

        for message in result.newMessages {
            NucleusNotificationService.shared.notifyNewMail(message)
            try? appendActivity(
                ActivityItem(
                    title: "New Email",
                    detail: "\(message.fromName): \(message.subject)",
                    source: .gmail,
                    accountEmail: accounts.first(where: { $0.id == message.accountID })?.email
                )
            )
        }

        DockBadgeController.update(unreadCount: totalUnread)
        statusMessage = statusMessageForCurrentState()
    }

    func syncCalendar() async {
        guard !accounts.isEmpty else { return }

        statusMessage = "Syncing calendar…"
        let events = await CalendarSyncEngine.sync(
            accounts: accounts,
            accessTokenProvider: { accountID in
                try await AccountSessionStore.shared.validAccessToken(accountID: accountID)
            }
        )

        calendarEvents = events
        let context = ModelContext(modelContainer)
        try? CalendarRepository.replaceEvents(events, context: context)
        scheduleMeetingReminders(for: events)
        statusMessage = statusMessageForCurrentState()
    }

    func filteredClipboardEntries() -> [ClipboardEntry] {
        ClipboardSearch.rank(clipboardEntries, query: clipboardSearchQuery)
    }

    func toggleClipboardPin(_ entry: ClipboardEntry) {
        let context = ModelContext(modelContainer)
        try? ClipboardRepository.setPinned(id: entry.id, pinned: !entry.isPinned, context: context)
        reloadLocalData()
    }

    func saveClipboardToNote(_ entry: ClipboardEntry) async {
        let note = NoteDocument(
            title: "Clipboard \(NucleusFormatters.time.string(from: Date()))",
            markdown: NotesMarkdown.clipboardNoteTemplate(from: entry.content, source: entry.sourceApplication),
            folder: .clipboardNotes
        )
        await saveNote(note)
    }

    func saveNote(_ note: NoteDocument) async {
        let context = ModelContext(modelContainer)
        var updated = note
        updated.updatedAt = Date()

        if let notesAccount = accounts.first(where: { $0.isPrimaryNotesAccount }) ?? accounts.first {
            do {
                let token = try await AccountSessionStore.shared.validAccessToken(accountID: notesAccount.id)
                let fileID = try await NotesSyncEngine.uploadNote(note: updated, accessToken: token)
                updated.driveFileID = fileID
                statusMessage = "Saved note to Google Drive"
            } catch {
                statusMessage = "Saved note locally (Drive upload pending auth)"
            }
        }

        try? NoteRepository.upsert(updated, context: context)
        reloadLocalData()
        selectedNoteID = updated.id

        try? appendActivity(
            ActivityItem(
                title: "Note saved",
                detail: updated.title,
                source: .notes
            )
        )
    }

    func createNote(in folder: NoteFolder) async {
        let note = NoteDocument(
            title: "Untitled",
            markdown: "# Untitled\n",
            folder: folder
        )
        await saveNote(note)
    }

    func sendQuickReply(body: String) async {
        guard let context = quickReplyContext else { return }
        do {
            let token = try await AccountSessionStore.shared.validAccessToken(accountID: context.accountID)
            try await GmailAPIClient.sendReply(
                accessToken: token,
                threadID: context.threadID,
                to: context.to,
                subject: context.subject,
                body: body
            )
            quickReplyContext = nil
            statusMessage = "Reply sent"
            await syncMail()
        } catch {
            statusMessage = "Reply failed"
        }
    }

    func markMessageRead(messageID: String, accountID: UUID) async {
        do {
            let token = try await AccountSessionStore.shared.validAccessToken(accountID: accountID)
            try await GmailAPIClient.markRead(accessToken: token, messageID: messageID)
            await syncMail()
        } catch {
            statusMessage = "Could not mark message read"
        }
    }

    private func handleClipboardCapture(_ capture: ClipboardCapture) {
        let entry = capture.asEntry()
        let context = ModelContext(modelContainer)
        try? ClipboardRepository.insert(entry, context: context)
        reloadLocalData()
        NucleusNotificationService.shared.notifyClipboardSaved(entry)
        try? appendActivity(
            ActivityItem(
                title: "Clipboard saved",
                detail: String(entry.content.prefix(80)),
                source: .clipboard
            )
        )
    }

    private func handleMailNotificationAction(_ action: NucleusNotificationService.MailNotificationAction) {
        switch action {
        case .open(_, let accountID):
            AppSettings.shared.selectedMailAccountID = accountID
            sidebarSelection = .workspace(.inbox)
        case .markRead(let messageID, let accountID):
            Task { await markMessageRead(messageID: messageID, accountID: accountID) }
        case .quickReply(_, let threadID, let accountID, let to, let subject):
            quickReplyContext = QuickReplyContext(
                messageID: "",
                threadID: threadID,
                accountID: accountID,
                to: to,
                subject: subject
            )
        }
    }

    private func scheduleMeetingReminders(for events: [CalendarEventSummary]) {
        let reminders = MeetingReminderPlanner.reminders(for: events)
        for reminder in reminders {
            let key = "\(reminder.event.id)-\(reminder.kind.rawValue)"
            guard !scheduledReminderKeys.contains(key) else { continue }
            scheduledReminderKeys.insert(key)

            let delay = reminder.fireDate.timeIntervalSinceNow
            guard delay > 0 else { continue }

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                NucleusNotificationService.shared.notifyMeetingReminder(reminder.event, kind: reminder.kind)
                try? self?.appendActivity(
                    ActivityItem(
                        title: "Meeting reminder",
                        detail: reminder.event.title,
                        source: .calendar,
                        accountEmail: reminder.event.accountEmail
                    )
                )
            }
        }
    }

    private func appendActivity(_ item: ActivityItem) throws {
        let context = ModelContext(modelContainer)
        try ActivityRepository.append(item, context: context)
        activityFeed.insert(item, at: 0)
    }

    private func seedDemoDataIfNeeded() {
        let context = ModelContext(modelContainer)
        guard (try? AccountRepository.fetchAll(context: context))?.isEmpty == true else { return }

        let demoAccounts = [
            GoogleAccount(email: "personal@gmail.com", displayName: "Personal", isPrimary: true, isPrimaryNotesAccount: true),
            GoogleAccount(email: "work@gmail.com", displayName: "Work"),
            GoogleAccount(email: "client@gmail.com", displayName: "Client"),
        ]
        for account in demoAccounts {
            try? AccountRepository.upsert(account, context: context)
        }

        let now = Date()
        let demoEvents = [
            CalendarEventSummary(
                id: "demo-1",
                accountID: demoAccounts[1].id,
                title: "Team Standup",
                startDate: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now,
                endDate: Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: now) ?? now,
                meetingLink: "https://meet.google.com/demo-standup",
                accountEmail: demoAccounts[1].email
            ),
            CalendarEventSummary(
                id: "demo-2",
                accountID: demoAccounts[2].id,
                title: "Client Meeting",
                startDate: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now,
                endDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: now) ?? now,
                accountEmail: demoAccounts[2].email
            ),
        ]
        try? CalendarRepository.replaceEvents(demoEvents, context: context)

        let demoClip = ClipboardEntry(
            content: "kubectl get pods -A",
            contentType: "command",
            sourceApplication: "Visual Studio Code",
            tags: ["kubernetes", "command"],
            capturedAt: now.addingTimeInterval(-120)
        )
        try? ClipboardRepository.insert(demoClip, context: context)

        let demoNote = NoteDocument(
            title: "Meeting Notes",
            markdown: """
            # Meeting Notes
            Date: \(NucleusFormatters.dayHeader.string(from: now))

            Discussion:
            - Production deployment
            - Kubernetes migration
            """,
            folder: .meetingNotes
        )
        try? NoteRepository.upsert(demoNote, context: context)

        reloadLocalData()
        unreadByAccount = [
            demoAccounts[0].id: 5,
            demoAccounts[1].id: 8,
            demoAccounts[2].id: 2,
        ]
        totalUnread = 15
        DockBadgeController.update(unreadCount: totalUnread)
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
