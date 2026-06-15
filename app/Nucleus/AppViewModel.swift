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
        await AccountSessionStore.shared.updateConfiguration(settings.oauthConfiguration)
        completeStartupStep(.accounts)

        await beginStartupStep(.clipboard, message: "Starting clipboard monitor…")
        ClipboardMonitorService.shared.onCapture = { [weak self] capture in
            Task { @MainActor in
                self?.handleClipboardCapture(capture)
            }
        }
        ClipboardMonitorService.shared.start()
        completeStartupStep(.clipboard)
        ClipboardPasteController.shared.start()

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

        purgeUnauthenticatedAccounts()
        DockBadgeController.update(unreadCount: totalUnread)
        startupMessage = "Nucleus is ready"
        startupProgressFraction = 1
        try? await Task.sleep(nanoseconds: 250_000_000)
        isStartingUp = false
        statusMessage = statusMessageForCurrentState()
        await promptSignInIfNeeded(settings: settings)
    }

    func promptSignInIfNeeded(settings: AppSettings) async {
        purgeUnauthenticatedAccounts()

        guard accounts.isEmpty else { return }

        sidebarSelection = .workspace(.accounts)
        statusMessage = "Add a Google account to begin"
    }

    func isAccountConnected(_ account: GoogleAccount) -> Bool {
        switch account.authMode {
        case .oauth:
            return hasStoredTokens(for: account.id)
        case .webSession:
            return true
        }
    }

    func purgeUnauthenticatedAccounts() {
        let stale = accounts.filter { !isAccountConnected($0) }
        guard !stale.isEmpty else { return }

        let context = ModelContext(modelContainer)
        for account in stale {
            try? AccountRepository.delete(id: account.id, context: context)
        }
        reloadLocalData()
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

    func hasStoredTokens(for accountID: UUID) -> Bool {
        KeychainTokenStore.shared.hasTokens(accountID: accountID)
    }

    var oauthAccounts: [GoogleAccount] {
        accounts.filter(\.usesOAuthAPI)
    }

    func addWebGmailAccount(email: String, categoryName: String) {
        oauthError = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedEmail.contains("@") else {
            oauthError = "Enter a valid Gmail address."
            return
        }

        if accounts.contains(where: { $0.email.lowercased() == trimmedEmail }) {
            oauthError = "That Gmail address is already added."
            if let existing = accounts.first(where: { $0.email.lowercased() == trimmedEmail }) {
                AppSettings.shared.selectedMailAccountID = existing.id
                sidebarSelection = .workspace(.inbox)
            }
            return
        }

        let trimmedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedCategory.isEmpty ? trimmedEmail : trimmedCategory

        let account = GoogleAccount(
            email: trimmedEmail,
            displayName: resolvedName,
            isPrimary: accounts.isEmpty,
            isPrimaryNotesAccount: false,
            authMode: .webSession
        )

        let context = ModelContext(modelContainer)
        try? AccountRepository.upsert(account, context: context)
        reloadLocalData()
        AppSettings.shared.selectedMailAccountID = account.id
        sidebarSelection = .workspace(.inbox)
        statusMessage = "Sign in to Gmail for \(trimmedEmail)"
    }

    func addGoogleAccount(settings: AppSettings, categoryName: String? = nil) async {
        oauthError = nil

        do {
            let (tokens, profile) = try await GoogleOAuthCoordinator.shared.signIn(
                configuration: settings.oauthConfiguration,
                clientSecret: nil
            )

            let trimmedCategory = categoryName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = trimmedCategory?.isEmpty == false ? trimmedCategory! : profile.name

            let account = GoogleAccount(
                email: profile.email,
                displayName: resolvedName,
                avatarURL: profile.picture ?? "",
                isPrimary: accounts.isEmpty,
                isPrimaryNotesAccount: accounts.isEmpty
            )

            try KeychainTokenStore.shared.saveTokens(tokens, accountID: account.id)

            let context = ModelContext(modelContainer)
            try AccountRepository.upsert(account, context: context)
            reloadLocalData()
            AppSettings.shared.selectedMailAccountID = account.id
            sidebarSelection = .workspace(.inbox)
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
        if account.authMode == .webSession {
            GmailWebSessionStore.clear(for: account.id)
        }
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

    func updateAccountCategory(_ account: GoogleAccount, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = account
        updated.displayName = trimmed
        let context = ModelContext(modelContainer)
        try? AccountRepository.upsert(updated, context: context)
        reloadLocalData()
        statusMessage = "Renamed category to \(trimmed)"
    }

    func syncMail() async {
        let apiAccounts = oauthAccounts
        guard !apiAccounts.isEmpty else {
            if accounts.allSatisfy({ $0.authMode == .webSession }) {
                totalUnread = 0
                DockBadgeController.update(unreadCount: 0)
            }
            return
        }

        statusMessage = "Syncing mail…"
        let result = await MailSyncEngine.sync(
            accounts: apiAccounts,
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
        let apiAccounts = oauthAccounts
        guard !apiAccounts.isEmpty else { return }

        statusMessage = "Syncing calendar…"
        let events = await CalendarSyncEngine.sync(
            accounts: apiAccounts,
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
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
