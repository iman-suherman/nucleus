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
    @Published var chatUnreadByAccount: [UUID: Int] = [:]
    @Published var totalUnread = 0
    @Published var totalChatUnread = 0
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
    private var webReportedUnread: [UUID: Int] = [:]
    private var unreadBaselineEstablished = Set<UUID>()
    private var webReportedChatUnread: [UUID: Int] = [:]
    private var chatUnreadBaselineEstablished = Set<UUID>()
    private var webReportedCalendarEvents: [UUID: [CalendarEventSummary]] = [:]

    init() {
        modelContainer = (try? NucleusDatabase.makeContainer()) ?? {
            fatalError("Failed to create Nucleus database container")
        }()
        AppViewModel.current = self
        observeGmailWebSignIn()
        observeGmailWebUnreadCount()
        observeChatWebUnreadCount()
        observeCalendarWebEvents()
    }

    private func observeCalendarWebEvents() {
        NotificationCenter.default.addObserver(
            forName: .calendarWebEventsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  let labels = notification.userInfo?["labels"] as? [String] else { return }
            self?.applyWebCalendarEvents(accountID: accountID, labels: labels)
        }
    }

    func applyWebCalendarEvents(accountID: UUID, labels: [String]) {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        let events = CalendarWebEventParser.parse(labels: labels, account: account)
        guard !events.isEmpty else { return }
        webReportedCalendarEvents[accountID] = events
        Task { await syncCalendar() }
    }

    private func observeGmailWebUnreadCount() {
        NotificationCenter.default.addObserver(
            forName: .gmailWebUnreadCountDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  let count = notification.userInfo?["count"] as? Int else { return }
            self?.applyWebUnreadCount(accountID: accountID, count: count)
        }
    }

    func applyWebUnreadCount(accountID: UUID, count: Int) {
        let previous = webReportedUnread[accountID] ?? 0
        webReportedUnread[accountID] = max(0, count)
        unreadByAccount[accountID] = max(0, count)
        totalUnread = unreadByAccount.values.reduce(0, +)
        DockBadgeController.update(unreadCount: totalUnread)
        statusMessage = statusMessageForCurrentState()

        if unreadBaselineEstablished.contains(accountID), count > previous {
            let account = accounts.first(where: { $0.id == accountID })
            NucleusNotificationService.shared.notifyIncomingMail(
                unreadCount: count,
                delta: count - previous,
                accountName: account?.displayName ?? account?.email ?? "Inbox"
            )
        }
        unreadBaselineEstablished.insert(accountID)

        Task { await syncCalendar() }
    }

    private func observeChatWebUnreadCount() {
        NotificationCenter.default.addObserver(
            forName: .chatWebUnreadCountDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  let count = notification.userInfo?["count"] as? Int else { return }
            self?.applyWebChatUnreadCount(accountID: accountID, count: count)
        }
    }

    func applyWebChatUnreadCount(accountID: UUID, count: Int) {
        let previous = webReportedChatUnread[accountID] ?? 0
        webReportedChatUnread[accountID] = max(0, count)
        chatUnreadByAccount[accountID] = max(0, count)
        totalChatUnread = chatUnreadByAccount.values.reduce(0, +)

        if chatUnreadBaselineEstablished.contains(accountID), count > previous {
            let account = accounts.first(where: { $0.id == accountID })
            NucleusNotificationService.shared.notifyIncomingChat(
                unreadCount: count,
                delta: count - previous,
                accountName: account?.displayName ?? account?.email ?? "Chat"
            )
        }
        chatUnreadBaselineEstablished.insert(accountID)
    }

    private func observeGmailWebSignIn() {
        NotificationCenter.default.addObserver(
            forName: .gmailWebSessionDidSignIn,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.syncMail()
                await self?.syncCalendar()
            }
        }
    }

    func bootstrap(settings: AppSettings) async {
        isStartingUp = true
        startupCompletedSteps = []
        startupActiveStep = nil
        startupProgressFraction = 0

        await beginStartupStep(.database, message: "Loading workspace data…")
        AuthStateMigration.resetStoredLoginIfNeeded(modelContainer: modelContainer)
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
        NucleusNotificationService.shared.onMeetingReminder = { [weak self] event, _ in
            Task { @MainActor in
                try? self?.appendActivity(
                    ActivityItem(
                        title: "Meeting reminder",
                        detail: event.title,
                        source: .calendar,
                        accountEmail: event.accountEmail
                    )
                )
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
            AppSettings.shared.selectedCalendarAccountID = primary.id
            AppSettings.shared.selectedChatAccountID = primary.id
        }
    }

    func calendarEvents(for accountID: UUID?) -> [CalendarEventSummary] {
        guard let accountID else { return calendarEvents }
        return calendarEvents.filter { $0.accountID == accountID }
    }

    func upcomingEvents(limit: Int = 8) -> [CalendarEventSummary] {
        let now = Date()
        return calendarEvents
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { $0 }
    }

    var todaysUpcomingMeetingCount: Int {
        let calendar = Calendar.current
        let now = Date()
        return calendarEvents.filter { event in
            calendar.isDateInToday(event.startDate) && event.endDate > now
        }.count
    }

    func accountDisplayName(for accountID: UUID) -> String {
        accounts.first(where: { $0.id == accountID })?.displayName ?? calendarEvents.first(where: { $0.accountID == accountID })?.accountEmail ?? "Calendar"
    }

    func openCalendar(for event: CalendarEventSummary) {
        AppSettings.shared.selectedCalendarAccountID = event.accountID
        sidebarSelection = .workspace(.calendar)
    }

    func openChat(for accountID: UUID) {
        AppSettings.shared.selectedChatAccountID = accountID
        sidebarSelection = .workspace(.chat)
    }

    func hasStoredTokens(for accountID: UUID) -> Bool {
        KeychainTokenStore.shared.hasTokens(accountID: accountID)
    }

    var oauthAccounts: [GoogleAccount] {
        accounts.filter(\.usesOAuthAPI)
    }

    var webSessionAccounts: [GoogleAccount] {
        accounts.filter { $0.authMode == .webSession }
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
                AppSettings.shared.selectedCalendarAccountID = existing.id
                AppSettings.shared.selectedChatAccountID = existing.id
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
        AppSettings.shared.selectedCalendarAccountID = account.id
        AppSettings.shared.selectedChatAccountID = account.id
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
            AppSettings.shared.selectedCalendarAccountID = account.id
            AppSettings.shared.selectedChatAccountID = account.id
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
            Task { @MainActor in
                await GmailWebSessionStore.clear(for: account.id)
            }
        }
        let context = ModelContext(modelContainer)
        try? AccountRepository.delete(id: account.id, context: context)
        reloadLocalData()
    }

    func setPrimaryAccount(_ account: GoogleAccount) {
        let context = ModelContext(modelContainer)
        try? AccountRepository.setPrimary(id: account.id, context: context)
        AppSettings.shared.selectedMailAccountID = account.id
        AppSettings.shared.selectedCalendarAccountID = account.id
        AppSettings.shared.selectedChatAccountID = account.id
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
        guard !accounts.isEmpty else {
            totalUnread = 0
            unreadByAccount = [:]
            DockBadgeController.update(unreadCount: 0)
            return
        }

        statusMessage = "Syncing mail…"
        var mergedUnread: [UUID: Int] = [:]
        var mergedMessages: [MailMessageSummary] = []
        var mergedNew: [MailMessageSummary] = []

        let apiAccounts = oauthAccounts
        if !apiAccounts.isEmpty {
            let result = await MailSyncEngine.sync(
                accounts: apiAccounts,
                knownMessageIDs: knownMessageIDs,
                accessTokenProvider: { accountID in
                    try await AccountSessionStore.shared.validAccessToken(accountID: accountID)
                }
            )
            mergedUnread.merge(result.unreadByAccount) { _, new in new }
            mergedMessages.append(contentsOf: result.messages)
            mergedNew.append(contentsOf: result.newMessages)
        }

        for account in accounts where account.authMode == .webSession {
            let cookies = await GmailWebSessionStore.cookies(for: account.id)
            let result = await GmailWebSessionClient.sync(
                account: account,
                cookies: cookies,
                knownMessageIDs: knownMessageIDs
            )
            let atomUnread = result.unreadByAccount[account.id] ?? 0
            let webUnread = webReportedUnread[account.id] ?? 0
            mergedUnread[account.id] = max(atomUnread, webUnread)
            mergedMessages.append(contentsOf: result.messages)
            mergedNew.append(contentsOf: result.newMessages)
        }

        unreadByAccount = mergedUnread
        totalUnread = mergedUnread.values.reduce(0, +)
        mailMessages = mergedMessages.sorted { $0.receivedAt > $1.receivedAt }
        knownMessageIDs.formUnion(mergedMessages.map(\.id))

        let context = ModelContext(modelContainer)
        try? MailRepository.replaceMessages(mergedMessages, context: context)

        for message in mergedNew.sorted(by: { $0.receivedAt > $1.receivedAt }) {
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
        guard !accounts.isEmpty else {
            calendarEvents = []
            await NucleusNotificationService.shared.rescheduleMeetingReminders([])
            return
        }

        statusMessage = "Syncing calendar…"
        var allEvents: [CalendarEventSummary] = []

        let apiAccounts = oauthAccounts
        if !apiAccounts.isEmpty {
            allEvents.append(
                contentsOf: await CalendarSyncEngine.sync(
                    accounts: apiAccounts,
                    accessTokenProvider: { accountID in
                        try await AccountSessionStore.shared.validAccessToken(accountID: accountID)
                    }
                )
            )
        }

        for account in accounts where account.authMode == .webSession {
            let cookies = await GmailWebSessionStore.cookies(for: account.id)
            let icalEvents = await CalendarWebSessionClient.sync(account: account, cookies: cookies)
            let webEvents = webReportedCalendarEvents[account.id] ?? []
            allEvents.append(
                contentsOf: CalendarWebSessionClient.mergeEvents(icalEvents: icalEvents, webEvents: webEvents)
            )
        }

        calendarEvents = allEvents.sorted { $0.startDate < $1.startDate }
        let context = ModelContext(modelContainer)
        try? CalendarRepository.replaceEvents(calendarEvents, context: context)
        await scheduleMeetingReminders(for: calendarEvents)
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

    private func scheduleMeetingReminders(for events: [CalendarEventSummary]) async {
        let reminders = MeetingReminderPlanner.reminders(for: events)
        await NucleusNotificationService.shared.rescheduleMeetingReminders(reminders)
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
