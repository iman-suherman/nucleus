import AccountKit
import ClipboardKit
import Combine
import DatabaseKit
import Foundation
import MailKit
import NotesKit
import NucleusKit
import SwiftData
import SwiftUI
import SyncKit

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
final class AppViewModel: ObservableObject, SyncedLayoutApplying {
    static weak var current: AppViewModel?

    @Published var sidebarSelection: SidebarSelection = .workspace(.inbox)
    @Published var accounts: [GoogleAccount] = []
    @Published var clipboardEntries: [ClipboardEntry] = []
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
    @Published var showWhatsNew = false
    @Published var whatsNewRelease: AppReleaseNotes?
    @Published var quickReplyContext: QuickReplyContext?
    @Published var accountError: String?
    @Published var webSessionStatus: [UUID: Bool] = [:]
    @Published var oauthConnectionStatus: [UUID: Bool] = [:]

    let modelContainer: ModelContainer
    let syncService = CloudKitSyncService.shared
    private let mailSyncService = MailSyncService()
    private var knownMessageIDs = Set<String>()
    private var webReportedUnread: [UUID: Int] = [:]
    private var unreadBaselineEstablished = Set<UUID>()
    private var webReportedChatUnread: [UUID: Int] = [:]
    private var chatUnreadBaselineEstablished = Set<UUID>()
    private var notifiedMessageIDs = Set<String>()
    private var pendingMailNotificationDeltas: [UUID: Int] = [:]

    init() {
        if ProcessInfo.processInfo.environment["NUCLEUS_SEED_CLOUDKIT_SCHEMA"] == "1" {
            NucleusDatabase.seedDevelopmentCloudKitSchemaIfNeeded(force: true)
        }

        modelContainer = (try? NucleusDatabase.makeContainer()) ?? {
            fatalError("Failed to create Nucleus database container")
        }()
        AppViewModel.current = self
        observeGmailWebSignIn()
        observeGmailWebUnreadCount()
        observeChatWebUnreadCount()
        observeCloudKitChanges()
        startWindowLayoutTracking()
    }

    func applySyncedLayout(from settings: AppSettings) {
        if let raw = settings.selectedWorkspacePane,
           let pane = WorkspacePane(rawValue: raw) {
            sidebarSelection = .workspace(pane)
        }
    }

    func sidebarSelectionDidChange(_ selection: SidebarSelection) {
        guard case .workspace(let pane) = selection else { return }
        AppSettings.shared.selectedWorkspacePane = pane.rawValue
        pushSyncedConfiguration()
    }

    func updateNotesListWidth(_ width: CGFloat) {
        var layout = AppSettings.shared.windowLayout ?? WindowLayoutState(width: 1320, height: 880)
        guard abs((layout.notesListWidth ?? 280) - Double(width)) > 4 else { return }
        layout.notesListWidth = Double(width)
        AppSettings.shared.windowLayout = layout
        scheduleLayoutPush()
    }

    private var layoutPushTask: Task<Void, Never>?
    private var layoutSaveTask: Task<Void, Never>?

    private func startWindowLayoutTracking() {
        WindowLayoutController.shared.startTracking { [weak self] layout in
            guard let self else { return }
            self.layoutSaveTask?.cancel()
            self.layoutSaveTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                var merged = AppSettings.shared.windowLayout ?? layout
                merged.width = layout.width
                merged.height = layout.height
                merged.originX = layout.originX
                merged.originY = layout.originY
                AppSettings.shared.windowLayout = merged
            }
        }
    }

    private func scheduleLayoutPush() {
        layoutPushTask?.cancel()
        layoutPushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            pushSyncedConfiguration()
        }
    }

    private func observeCloudKitChanges() {
        NotificationCenter.default.addObserver(
            forName: .nucleusCloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadLocalData()
                await self?.refreshWebSessionStatus()
            }
        }
    }

    private func observeGmailWebUnreadCount() {
        NotificationCenter.default.addObserver(
            forName: .gmailWebUnreadCountDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let accountID = NotificationUserInfo.accountID(from: notification.userInfo),
                  let count = NotificationUserInfo.unreadCount(from: notification.userInfo) else { return }
            self?.applyWebUnreadCount(accountID: accountID, count: count)
        }
    }

    func applyWebUnreadCount(accountID: UUID, count: Int) {
        let previous = webReportedUnread[accountID] ?? 0
        let hadBaseline = unreadBaselineEstablished.contains(accountID)
        webReportedUnread[accountID] = max(0, count)
        unreadByAccount[accountID] = max(0, count)
        totalUnread = unreadByAccount.values.reduce(0, +)
        DockBadgeController.update(unreadCount: totalUnread)
        statusMessage = statusMessageForCurrentState()
        unreadBaselineEstablished.insert(accountID)

        if hadBaseline, count > previous {
            pendingMailNotificationDeltas[accountID, default: 0] += count - previous
            Task { await syncMail() }
        }
    }

    @discardableResult
    private func deliverMailNotifications(
        accountID: UUID,
        preferredMessages: [MailMessageSummary] = [],
        limit: Int
    ) -> Int {
        guard limit > 0 else { return 0 }

        var delivered = 0
        var seen = Set<String>()
        let accountName = accounts.first(where: { $0.id == accountID })?.displayName
            ?? accounts.first(where: { $0.id == accountID })?.email
            ?? "Inbox"

        let orderedCandidates = (preferredMessages + mailMessages)
            .filter { message in
                message.accountID == accountID
                    && message.isUnread
                    && !notifiedMessageIDs.contains(message.id)
                    && seen.insert(message.id).inserted
            }
            .sorted { $0.receivedAt > $1.receivedAt }

        for message in orderedCandidates.prefix(limit) {
            NucleusNotificationService.shared.notifyNewMail(message, accountName: accountName)
            notifiedMessageIDs.insert(message.id)
            delivered += 1
        }

        return delivered
    }

    private func flushPendingMailNotifications() {
        for account in accounts {
            guard let delta = pendingMailNotificationDeltas[account.id], delta > 0 else { continue }
            let delivered = deliverMailNotifications(accountID: account.id, limit: delta)
            if delivered == 0 {
                let accountName = account.displayName.isEmpty ? account.email : account.displayName
                NucleusNotificationService.shared.notifyIncomingMail(
                    unreadCount: unreadByAccount[account.id] ?? delta,
                    delta: delta,
                    accountName: accountName,
                    accountID: account.id
                )
            }
            pendingMailNotificationDeltas.removeValue(forKey: account.id)
        }
    }

    private func observeChatWebUnreadCount() {
        NotificationCenter.default.addObserver(
            forName: .chatWebUnreadCountDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let accountID = NotificationUserInfo.accountID(from: notification.userInfo),
                  let count = NotificationUserInfo.unreadCount(from: notification.userInfo) else { return }
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
                await self?.refreshWebSessionStatus()
                await self?.syncMail()
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
        completeStartupStep(.accounts)

        await beginStartupStep(.icloudSync, message: "Syncing configuration via iCloud…")
        syncService.start()
        SettingsSyncBridge.shared.start(
            modelContainer: modelContainer,
            settings: settings,
            layoutDelegate: self
        )
        await syncService.refreshAccountStatus()
        try? await Task.sleep(nanoseconds: 350_000_000)
        reloadLocalData()
        reconcileSelectedAccounts(settings: settings)
        applySyncedLayout(from: settings)
        await refreshWebSessionStatus()
        completeStartupStep(.icloudSync)

        await beginStartupStep(.keychainSync, message: "Restoring Google credentials…")
        await autoReconnectAccounts(settings: settings)
        completeStartupStep(.keychainSync)

        await beginStartupStep(.clipboard, message: "Starting clipboard monitor…")
        ClipboardMonitorService.shared.isCaptureEnabled = { settings.clipboardSyncEnabled }
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
        NucleusNotificationService.shared.onMeetingReminder = nil
        await NucleusNotificationService.shared.rescheduleMeetingReminders([])
        MailNotificationSound.prepareNotificationSounds()
        completeStartupStep(.notifications)

        await beginStartupStep(.mailSync, message: "Syncing mail…")
        mailSyncService.start(viewModel: self, interval: settings.mailSyncInterval)
        await syncMail()
        completeStartupStep(.mailSync)

        DockBadgeController.update(unreadCount: totalUnread)
        startupMessage = "Nucleus is ready"
        startupProgressFraction = 1
        try? await Task.sleep(nanoseconds: 250_000_000)
        isStartingUp = false
        statusMessage = statusMessageForCurrentState()
        presentWhatsNewIfNeeded()
        await promptSignInIfNeeded(settings: settings)
    }

    func dismissWhatsNew() {
        ReleaseNotesLoader.markCurrentVersionSeen()
        showWhatsNew = false
        whatsNewRelease = nil
    }

    private func presentWhatsNewIfNeeded() {
        guard ReleaseNotesLoader.shouldPresentWhatsNew() else { return }
        guard let release = ReleaseNotesLoader.loadCurrentRelease() else { return }
        whatsNewRelease = release
        showWhatsNew = true
    }

    func promptSignInIfNeeded(settings: AppSettings) async {
        await refreshWebSessionStatus()
        await autoReconnectAccounts(settings: settings)

        if accounts.isEmpty {
            sidebarSelection = .workspace(.accounts)
            statusMessage = "Add a Gmail account to begin"
            return
        }

        let needsSignIn = accounts.filter { needsReconnect(for: $0) }
        guard !needsSignIn.isEmpty else {
            statusMessage = statusMessageForCurrentState()
            return
        }

        sidebarSelection = .workspace(.accounts)
        if needsSignIn.count == 1, let account = needsSignIn.first {
            statusMessage = "Sign in to \(account.displayName.isEmpty ? account.email : account.displayName) on this Mac"
        } else {
            statusMessage = "Sign in to \(needsSignIn.count) Google accounts on this Mac"
        }
    }

    func autoReconnectAccounts(settings: AppSettings) async {
        await GoogleOAuthConfigurationLoader.loadIntoSessionStore(
            tokenSynchronizable: settings.iCloudKeychainTokenSyncEnabled
        )

        if settings.iCloudKeychainTokenSyncEnabled {
            KeychainTokenStore.shared.migrateAllToSynchronizable(accountIDs: accounts.map(\.id))
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        } else {
            KeychainTokenStore.shared.migrateAllToLocalOnly(accountIDs: accounts.map(\.id))
        }

        guard GoogleOAuthConfigurationLoader.isConfigured else {
            oauthConnectionStatus = [:]
            return
        }

        var status: [UUID: Bool] = [:]
        for account in accounts {
            guard KeychainTokenStore.shared.hasTokens(accountID: account.id) else {
                status[account.id] = false
                continue
            }
            do {
                _ = try await AccountSessionStore.shared.validAccessToken(accountID: account.id)
                status[account.id] = true
            } catch {
                status[account.id] = false
            }
        }
        oauthConnectionStatus = status
    }

    func isOAuthConnected(_ account: GoogleAccount) -> Bool {
        oauthConnectionStatus[account.id] == true
    }

    func needsReconnect(for account: GoogleAccount) -> Bool {
        if isOAuthConnected(account), account.authMode == .oauth {
            return false
        }
        if account.authMode == .webSession {
            if isOAuthConnected(account) {
                return !(webSessionStatus[account.id] ?? false)
            }
            return !(webSessionStatus[account.id] ?? false)
        }
        return !isOAuthConnected(account)
    }

    func refreshWebSessionStatus() async {
        var status: [UUID: Bool] = [:]
        for account in webSessionAccounts {
            let cookies = await GmailWebSessionStore.cookies(for: account.id)
            status[account.id] = cookies.contains { $0.domain.contains("google.com") }
        }
        webSessionStatus = status
    }

    func reconnectAccount(_ account: GoogleAccount) {
        AppSettings.shared.selectedMailAccountID = account.id
        sidebarSelection = .workspace(.inbox)
        statusMessage = "Sign in to Gmail for \(account.displayName.isEmpty ? account.email : account.displayName)"
    }

    func isAccountConnected(_ account: GoogleAccount) -> Bool {
        switch account.authMode {
        case .oauth:
            return isOAuthConnected(account)
        case .webSession:
            return (webSessionStatus[account.id] ?? false) || isOAuthConnected(account)
        }
    }

    func purgeUnauthenticatedAccounts() {
        // Account metadata syncs via CloudKit; credentials restore through iCloud Keychain and web sign-in.
    }

    func checkForUpdatesWhenEligible() {
        SparkleUpdaterController.shared.checkForUpdatesInForegroundIfNeeded()
    }

    func refreshMailUnreadNow() {
        NotificationCenter.default.post(name: .gmailWebUnreadPollNow, object: nil)
    }

    private func statusMessageForCurrentState() -> String {
        if accounts.isEmpty {
            return "Add a Gmail account to begin"
        }
        if totalUnread > 0 {
            return "\(totalUnread) unread messages"
        }
        return "Ready"
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
        notes = (try? NoteRepository.fetchAll(context: context)) ?? []
        totalUnread = (try? MailRepository.unreadCount(context: context)) ?? 0

        if selectedNoteID == nil {
            selectedNoteID = notes.first?.id
        }
    }

    func reconcileSelectedAccounts(settings: AppSettings) {
        let accountIDs = Set(accounts.map(\.id))
        let fallback = accounts.first(where: { $0.isPrimary }) ?? accounts.first

        if let selected = settings.selectedMailAccountID, !accountIDs.contains(selected) {
            settings.selectedMailAccountID = fallback?.id
        } else if settings.selectedMailAccountID == nil {
            settings.selectedMailAccountID = fallback?.id
        }

        if let selected = settings.selectedCalendarAccountID, !accountIDs.contains(selected) {
            settings.selectedCalendarAccountID = fallback?.id
        } else if settings.selectedCalendarAccountID == nil {
            settings.selectedCalendarAccountID = fallback?.id
        }

        if let selected = settings.selectedChatAccountID, !accountIDs.contains(selected) {
            settings.selectedChatAccountID = fallback?.id
        } else if settings.selectedChatAccountID == nil {
            settings.selectedChatAccountID = fallback?.id
        }
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
        accountError = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedEmail.contains("@") else {
            accountError = "Enter a valid Gmail address."
            return
        }

        if accounts.contains(where: { $0.email.lowercased() == trimmedEmail }) {
            accountError = "That Gmail address is already added."
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
        pushSyncedConfiguration()
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
        AppSettings.shared.clearMailNotificationSound(for: account.id)
        EmbeddedWebViewRegistry.remove(accountID: account.id)
        reloadLocalData()
        pushSyncedConfiguration()
    }

    func setPrimaryAccount(_ account: GoogleAccount) {
        let context = ModelContext(modelContainer)
        try? AccountRepository.setPrimary(id: account.id, context: context)
        AppSettings.shared.selectedMailAccountID = account.id
        AppSettings.shared.selectedCalendarAccountID = account.id
        AppSettings.shared.selectedChatAccountID = account.id
        reloadLocalData()
        pushSyncedConfiguration()
    }

    func setPrimaryNotesAccount(_ account: GoogleAccount) {
        let context = ModelContext(modelContainer)
        try? AccountRepository.setPrimaryNotesAccount(id: account.id, context: context)
        reloadLocalData()
        pushSyncedConfiguration()
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
        pushSyncedConfiguration()
    }

    private func pushSyncedConfiguration() {
        SettingsSyncBridge.shared.pushNow(from: AppSettings.shared)
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
            let combinedUnread = max(atomUnread, webReportedUnread[account.id] ?? 0)
            webReportedUnread[account.id] = combinedUnread
            mergedUnread[account.id] = combinedUnread
            mergedMessages.append(contentsOf: result.messages)
            mergedNew.append(contentsOf: result.newMessages)
        }

        unreadByAccount = mergedUnread
        totalUnread = mergedUnread.values.reduce(0, +)
        mailMessages = mergedMessages.sorted { $0.receivedAt > $1.receivedAt }
        knownMessageIDs.formUnion(mergedMessages.map(\.id))

        let context = ModelContext(modelContainer)
        try? MailRepository.replaceMessages(mergedMessages, context: context)

        let newMessagesByAccount = Dictionary(grouping: mergedNew, by: \.accountID)
        for account in accounts {
            let newMessages = newMessagesByAccount[account.id] ?? []
            guard !newMessages.isEmpty else { continue }
            deliverMailNotifications(
                accountID: account.id,
                preferredMessages: newMessages.sorted { $0.receivedAt > $1.receivedAt },
                limit: newMessages.count
            )
            if var delta = pendingMailNotificationDeltas[account.id] {
                delta = max(0, delta - newMessages.count)
                if delta > 0 {
                    pendingMailNotificationDeltas[account.id] = delta
                } else {
                    pendingMailNotificationDeltas.removeValue(forKey: account.id)
                }
            }
        }

        flushPendingMailNotifications()

        DockBadgeController.update(unreadCount: totalUnread)
        statusMessage = statusMessageForCurrentState()
    }

    func filteredClipboardEntries() -> [ClipboardEntry] {
        ClipboardSearch.rank(clipboardEntries, query: clipboardSearchQuery)
    }

    func toggleClipboardPin(_ entry: ClipboardEntry) {
        let context = ModelContext(modelContainer)
        let pinning = !entry.isPinned
        try? ClipboardRepository.setPinned(id: entry.id, pinned: pinning, context: context)
        reloadLocalData()
        if pinning, AppSettings.shared.clipboardSaveToNotesEnabled {
            Task { await saveClipboardToNote(entry, selectNote: false) }
        }
    }

    func saveClipboardToNote(_ entry: ClipboardEntry, selectNote: Bool = true) async {
        let note = NoteDocument(
            title: "Clipboard \(NucleusFormatters.time.string(from: entry.capturedAt))",
            markdown: NotesMarkdown.clipboardNoteTemplate(
                from: entry.content,
                source: entry.sourceApplication,
                capturedAt: entry.capturedAt
            ),
            folder: .clipboardNotes
        )
        await saveNote(note, selectNote: selectNote)
    }

    func saveNote(_ note: NoteDocument, selectNote: Bool = true) async {
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
        if selectNote {
            selectedNoteID = updated.id
        }
    }

    func createNote(in folder: NoteFolder) async {
        let note: NoteDocument
        if folder.isSensitive {
            let title = "New Entry"
            note = NoteDocument(
                title: title,
                markdown: NotesMarkdown.credentialNoteTemplate(title: title, folder: folder),
                folder: folder
            )
        } else {
            note = NoteDocument(
                title: "Untitled",
                markdown: "# Untitled\n",
                folder: folder
            )
        }
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
        guard AppSettings.shared.clipboardSyncEnabled else { return }
        let entry = capture.asEntry()
        let context = ModelContext(modelContainer)
        try? ClipboardRepository.insert(entry, context: context)
        reloadLocalData()
        if AppSettings.shared.clipboardSaveToNotesEnabled {
            Task { await saveClipboardToNote(entry, selectNote: false) }
        }
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
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
