import AccountKit
import AppKit
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

    @Published var sidebarSelection: SidebarSelection = .workspace(.dashboard)
    @Published var settingsTabSelection: SettingsTab = .nucleusCloud
    @Published var accounts: [GoogleAccount] = []
    @Published var clipboardEntries: [ClipboardEntry] = []
    @Published var bills: [Bill] = []
    @Published var billPayments: [BillPayment] = []
    @Published var selectedBillID: UUID?
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
    @Published var clipboardPasswordSuggestion: ClipboardPasswordSuggestion?
    @Published private(set) var storedDashboardAnalysis: StoredDashboardAnalysis?
    @Published var dashboardAnalyzedAt: Date?
    @Published var dashboardQuote: String = DashboardQuotes.currentOrRandom()
    @Published var dashboardQuoteEmojis: String = ""
    @Published var clipboardDayAnalysis: DashboardClipboardDayAnalysis?
    @Published var accountError: String?
    @Published var webSessionStatus: [UUID: Bool] = [:]
    @Published var oauthConnectionStatus: [UUID: Bool] = [:]
    @Published private(set) var isMailBackgroundSyncInProgress = false
    let modelContainer: ModelContainer
    let syncService = CloudKitSyncService.shared
    let menuBarController = MenuBarController()
    let cloudSyncService = NucleusCloudSyncService.shared
    private let mailSyncService = MailSyncService()
    private var knownMessageIDs = Set<String>()
    private var webReportedUnread: [UUID: Int] = [:]
    private var unreadBaselineEstablished = Set<UUID>()
    private var webReportedChatUnread: [UUID: Int] = [:]
    private var chatUnreadBaselineEstablished = Set<UUID>()
    private var notifiedMessageIDs = Set<String>()
    private var pendingMailNotificationDeltas: [UUID: Int] = [:]
    private var mailUnreadSyncBaselineEstablished = Set<UUID>()
    private var mailSignInPendingAccountIDs = Set<UUID>()
    private var billReminderRefreshTask: Task<Void, Never>?
    private var billReminderSettingsObserver: AnyCancellable?
    private var menuBarSettingsObserver: AnyCancellable?
    private var dashboardQuoteEmojiTask: Task<Void, Never>?
    private var clipboardDayAnalysisTask: Task<Void, Never>?
    private var dismissedPasswordSuggestionHashes = Set<String>()
    private var isBootstrapping = false
    private var hasFinishedBootstrap = false
    private var bootstrapTask: Task<Void, Never>?

    init() {
        if ProcessInfo.processInfo.environment["NUCLEUS_SEED_CLOUDKIT_SCHEMA"] == "1" {
            NucleusDatabase.seedDevelopmentCloudKitSchemaIfNeeded(force: true)
        }

        CloudKitStoreMigration.resetIfNeeded()

        modelContainer = (try? NucleusDatabase.makeContainer()) ?? {
            fatalError("Failed to create Nucleus database container")
        }()
        AppViewModel.current = self
        runSynchronousLaunchPrep()
        observeGmailWebSignIn()
        observeGmailWebUnreadCount()
        observeChatWebUnreadCount()
        observeCloudKitChanges()
        observeNucleusCloudConnection()
        observeMenuBarSettings()
        startWindowLayoutTracking()
        observeBillReminderSettings()
    }

    private func runSynchronousLaunchPrep() {
        NSLog("Nucleus: sync launch prep starting")
        beginStartupStep(.database, message: "Loading workspace data…")
        if CloudKitStoreMigration.didResetThisLaunch {
            syncService.syncLogStore.log(
                "Local database reset for iCloud compatibility (v0.4.0). Re-add Google accounts and notes, then use Sync to iCloud in Settings.",
                level: .warning
            )
        }
        AuthStateMigration.resetStoredLoginIfNeeded(modelContainer: modelContainer)
        if NotesClipboardMigration.resetNotesForClipboardPolicyChange(modelContainer: modelContainer) {
            syncService.markNotesLocalChange()
        }
        reloadLocalData()
        completeStartupStep(.database)
        NSLog("Nucleus: sync launch prep finished")
    }

    func scheduleBootstrap(settings: AppSettings) {
        guard !hasFinishedBootstrap else { return }
        guard bootstrapTask == nil else { return }
        NSLog("Nucleus: bootstrap scheduled")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.hasFinishedBootstrap else { return }
            guard self.bootstrapTask == nil else { return }
            self.bootstrapTask = Task(priority: .userInitiated) { @MainActor [weak self] in
                guard let self else { return }
                await self.bootstrap(settings: settings)
                self.bootstrapTask = nil
            }
        }
    }

    private func observeMenuBarSettings() {
        menuBarSettingsObserver = AppSettings.shared.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isStartingUp else { return }
                self.menuBarController.applySettings(AppSettings.shared)
            }
    }

    private func observeNucleusCloudConnection() {
        NotificationCenter.default.addObserver(
            forName: .nucleusCloudDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.completeNucleusCloudConnection()
            }
        }
    }

    private func observeBillReminderSettings() {
        billReminderSettingsObserver = AppSettings.shared.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleBillReminderRefresh()
            }
    }

    func refreshBillReminders(settings: AppSettings = AppSettings.shared) async {
        await NucleusNotificationService.shared.rescheduleBillReminders(
            bills: activeBills,
            payments: billPayments,
            configuration: settings.billDueReminderConfiguration
        )
    }

    private func scheduleBillReminderRefresh() {
        billReminderRefreshTask?.cancel()
        billReminderRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await refreshBillReminders()
        }
    }

    func applySyncedLayout(from settings: AppSettings) {
        // Dashboard is always the launch entry point; window layout restores via AppSettings.windowLayout.
    }

    func sidebarSelectionDidChange(_ selection: SidebarSelection) {
        guard case .workspace(let pane) = selection else { return }
        AppSettings.shared.selectedWorkspacePane = pane.rawValue
        pushSyncedConfiguration()
        WorkspaceIdleController.shared.recordActivity()
    }

    func openSettings(tab: SettingsTab) {
        settingsTabSelection = tab
        sidebarSelection = .workspace(.settings)
        AppSettings.shared.selectedWorkspacePane = WorkspacePane.settings.rawValue
    }

    func openSystemICloudSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane",
            "x-apple.systempreferences:com.apple.AccountSettings",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
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
                guard let self, !self.isStartingUp else { return }
                self.reloadLocalData()
                await self.refreshWebSessionStatus()
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
        updateDockBadge()
        statusMessage = statusMessageForCurrentState()
        unreadBaselineEstablished.insert(accountID)

        if hadBaseline, count > previous {
            pendingMailNotificationDeltas[accountID, default: 0] += count - previous
            flushPendingMailNotifications()
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

    private func accumulateMailUnreadDeltas(from mergedUnread: [UUID: Int]) {
        for account in accounts {
            let accountID = account.id
            let newCount = mergedUnread[accountID] ?? 0
            let previous = unreadByAccount[accountID] ?? 0
            let hadBaseline = mailUnreadSyncBaselineEstablished.contains(accountID)

            if hadBaseline, newCount > previous {
                pendingMailNotificationDeltas[accountID, default: 0] += newCount - previous
            }
            mailUnreadSyncBaselineEstablished.insert(accountID)
        }
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
        updateDockBadge()
        statusMessage = statusMessageForCurrentState()

        if chatUnreadBaselineEstablished.contains(accountID), count > previous {
            let account = accounts.first(where: { $0.id == accountID })
            NucleusNotificationService.shared.notifyIncomingChat(
                unreadCount: count,
                delta: count - previous,
                accountName: account?.displayName ?? account?.email ?? "Chat",
                accountID: accountID
            )
        }
        chatUnreadBaselineEstablished.insert(accountID)
    }

    private func observeGmailWebSignIn() {
        NotificationCenter.default.addObserver(
            forName: .gmailWebSessionDidSignIn,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let accountID = notification.object as? UUID {
                    self?.clearMailSignInPending(accountID)
                }
                await self?.refreshWebSessionStatus()
                // Defer sync so Gmail can finish rendering after sign-in.
                try? await Task.sleep(nanoseconds: 200_000_000)
                await self?.syncMail()
            }
        }
    }

    func isMailSignInPending(_ accountID: UUID) -> Bool {
        mailSignInPendingAccountIDs.contains(accountID)
    }

    func markMailSignInPending(_ accountID: UUID) {
        mailSignInPendingAccountIDs.insert(accountID)
    }

    func clearMailSignInPending(_ accountID: UUID) {
        mailSignInPendingAccountIDs.remove(accountID)
    }

    func bootstrap(settings: AppSettings) async {
        guard !hasFinishedBootstrap else { return }
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        NSLog("Nucleus: bootstrap started")
        isStartingUp = true

        if !startupCompletedSteps.contains(.database) {
            beginStartupStep(.database, message: "Loading workspace data…")
            if CloudKitStoreMigration.didResetThisLaunch {
                syncService.syncLogStore.log(
                    "Local database reset for iCloud compatibility (v0.4.0). Re-add Google accounts and notes, then use Sync to iCloud in Settings.",
                    level: .warning
                )
            }
            AuthStateMigration.resetStoredLoginIfNeeded(modelContainer: modelContainer)
            if NotesClipboardMigration.resetNotesForClipboardPolicyChange(modelContainer: modelContainer) {
                syncService.markNotesLocalChange()
            }
            reloadLocalData()
            completeStartupStep(.database)
        }

        beginStartupStep(.accounts, message: "Restoring Google accounts…")
        completeStartupStep(.accounts)

        beginStartupStep(.icloudSync, message: "Syncing configuration via iCloud…")
        NSLog("Nucleus: bootstrap icloud step starting")
        syncService.registerModelContainer(modelContainer)
        syncService.start(refreshAccount: false)
        menuBarController.configure(modelContainer: modelContainer) { [weak self] in
            self?.reloadLocalData()
        }
        menuBarController.applySettings(settings, syncStatusItem: false)
        await syncService.refreshAccountStatus(includeDiagnostics: false, localOnly: true)
        reloadLocalData()
        reconcileSelectedAccounts(settings: settings)
        applySyncedLayout(from: settings)
        completeStartupStep(.icloudSync)
        NSLog("Nucleus: bootstrap icloud step finished")

        beginStartupStep(.keychainSync, message: "Restoring Google credentials…")
        await autoReconnectAccounts(settings: settings)
        completeStartupStep(.keychainSync)

        beginStartupStep(.clipboard, message: "Connecting clipboard companion…")
        completeStartupStep(.clipboard)
        ClipboardPasteController.shared.start()

        beginStartupStep(.notifications, message: "Preparing notifications…")
        NucleusNotificationService.shared.prepare()
        NucleusNotificationService.shared.registerCategories()
        NucleusNotificationService.shared.onMailAction = { [weak self] action in
            Task { @MainActor in
                self?.handleMailNotificationAction(action)
            }
        }
        NucleusNotificationService.shared.onClipboardPasswordAction = { [weak self] action in
            self?.handleClipboardPasswordNotificationAction(action)
        }
        NucleusNotificationService.shared.onMeetingReminder = nil
        await NucleusNotificationService.shared.rescheduleMeetingReminders([])
        await refreshBillReminders(settings: settings)
        MailNotificationSound.prepareNotificationSounds()
        ChatNotificationSound.prepareNotificationSounds()
        HourlyBeepService.shared.start()
        completeStartupStep(.notifications)

        beginStartupStep(.mailSync, message: "Syncing mail…")
        mailSyncService.start(viewModel: self, interval: settings.mailSyncInterval)
        completeStartupStep(.mailSync)
        Task { @MainActor in
            await syncMail()
        }
        DashboardAnalysisService.shared.start(viewModel: self)
        refreshDashboardQuoteEmojis()

        updateDockBadge()
        startupMessage = "Nucleus is ready"
        startupProgressFraction = 1
        try? await Task.sleep(nanoseconds: 250_000_000)
        isStartingUp = false
        MenuBarCoordinator.sync(settings: settings, controller: menuBarController)
        hasFinishedBootstrap = true
        sidebarSelection = .workspace(.dashboard)
        AppSettings.shared.selectedWorkspacePane = WorkspacePane.dashboard.rawValue
        statusMessage = statusMessageForCurrentState()
        scheduleDeferredCloudKitExportPrep()
        scheduleDeferredStartupSync()
        NSLog("Nucleus: bootstrap finished")
        WorkspaceIdleController.shared.start(viewModel: self)
        await presentWhatsNewIfNeeded()
        await promptSignInIfNeeded(settings: settings)
    }

    private func scheduleDeferredCloudKitExportPrep() {
        Task { @MainActor in
            let exportContext = ModelContext(modelContainer)
            if let exported = try? NucleusDatabase.exportNotesToCloudKit(context: exportContext), exported > 0 {
                syncService.markNotesLocalChange()
            }
            if let exported = try? NucleusDatabase.exportBillsToCloudKit(context: exportContext), exported > 0 {
                syncService.log("Queued \(exported) bill/payment record(s) for iCloud export on launch")
            }
            persistDashboardAnalysis()
            if let exported = try? NucleusDatabase.exportDashboardToCloudKit(context: exportContext), exported > 0 {
                syncService.log("Queued dashboard analysis for iCloud export on launch")
            }
        }
    }

    private func scheduleDeferredStartupSync() {
        Task(priority: .utility) { @MainActor in
            NSLog("Nucleus: deferred startup sync starting")
            let settings = AppSettings.shared
            SettingsSyncBridge.shared.start(
                modelContainer: modelContainer,
                settings: settings,
                layoutDelegate: self
            )
            await syncService.refreshAccountStatus(includeDiagnostics: true)
            if cloudSyncService.status.isConnected {
                let cloudContext = ModelContext(modelContainer)
                await cloudSyncService.syncNow(context: cloudContext)
                reloadLocalData()
            }
            await refreshWebSessionStatus()
            NSLog("Nucleus: deferred startup sync finished")
        }
    }

    func dismissWhatsNew() {
        ReleaseNotesLoader.markCurrentVersionSeen()
        showWhatsNew = false
        whatsNewRelease = nil
    }

    func presentCurrentReleaseNotes() async {
        let release = await ReleaseNotesLoader.loadCurrentReleaseAsync()
            ?? AppReleaseNotes(
                version: AppSettings.currentAppVersion,
                summary: "Nucleus \(AppSettings.currentAppVersion) is ready.",
                releaseNotes: .init()
            )
        whatsNewRelease = release
        showWhatsNew = true
    }

    private func presentWhatsNewIfNeeded() async {
        guard ReleaseNotesLoader.shouldPresentWhatsNew() else { return }
        guard let release = await ReleaseNotesLoader.loadCurrentReleaseAsync() else { return }
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
        if account.authMode == .webSession {
            markMailSignInPending(account.id)
        }
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
        Task { await syncMail() }
    }

    private func statusMessageForCurrentState() -> String {
        if accounts.isEmpty {
            return "Add a Gmail account to begin"
        }

        var parts: [String] = []
        if totalUnread > 0 {
            parts.append("\(totalUnread) unread email\(totalUnread == 1 ? "" : "s")")
        }
        if totalChatUnread > 0 {
            parts.append("\(totalChatUnread) unread chat\(totalChatUnread == 1 ? "" : "s")")
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        return "Ready"
    }

    func unreadBreakdown(for counts: [UUID: Int]) -> [UnreadAccountBreakdown] {
        accounts.compactMap { account in
            guard let count = counts[account.id], count > 0 else { return nil }
            let name = account.displayName.isEmpty ? account.email : account.displayName
            return UnreadAccountBreakdown(id: account.id, name: name, count: count)
        }
    }

    private func beginStartupStep(_ step: StartupStep, message: String) {
        startupActiveStep = step
        startupMessage = message
        refreshStartupProgress()
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
        try? ClipboardRepository.prune(context: context)
        accounts = (try? AccountRepository.fetchAll(context: context)) ?? []
        clipboardEntries = (try? ClipboardRepository.fetchRecent(context: context)) ?? []
        if clipboardDayAnalysis == nil,
           let cached = DashboardClipboardDayAnalysisService.cachedAnalysis() {
            clipboardDayAnalysis = cached
        }
        bills = (try? BillRepository.fetchAll(context: context)) ?? []
        billPayments = (try? BillRepository.fetchPayments(context: context)) ?? []
        notes = (try? NoteRepository.fetchAll(context: context)) ?? []
        if let stored = try? DashboardAnalysisRepository.fetch(context: context) {
            storedDashboardAnalysis = stored
            dashboardAnalyzedAt = stored.analyzedAt
        }

        let storedMessages = (try? MailRepository.fetchRecent(context: context)) ?? []
        mailMessages = storedMessages
        knownMessageIDs = Set(storedMessages.map(\.id))

        var storedUnreadByAccount: [UUID: Int] = [:]
        for account in accounts {
            storedUnreadByAccount[account.id] = (try? MailRepository.unreadCount(for: account.id, context: context)) ?? 0
        }
        if !storedUnreadByAccount.isEmpty {
            unreadByAccount = storedUnreadByAccount
            totalUnread = storedUnreadByAccount.values.reduce(0, +)
        } else {
            totalUnread = (try? MailRepository.unreadCount(context: context)) ?? 0
        }

        if !knownMessageIDs.isEmpty {
            mailUnreadSyncBaselineEstablished.formUnion(accounts.map(\.id))
        }

        if selectedNoteID == nil {
            selectedNoteID = notes.first?.id
        }
        if selectedBillID == nil {
            selectedBillID = activeBills.first?.id
        } else if !activeBills.contains(where: { $0.id == selectedBillID }) {
            selectedBillID = activeBills.first?.id
        }

        scheduleBillReminderRefresh()
        updateDockBadge()
        if !isStartingUp {
            menuBarController.reload()
        }
    }

    private func updateDockBadge() {
        DockBadgeController.update(
            mailUnread: totalUnread,
            chatUnread: totalChatUnread,
            billsDueSoon: billsDueDockBadgeCount
        )
    }

    var billsDueDockBadgeCount: Int {
        BillScheduleCalculator.dueWithinDaysOrOverdueCount(
            bills: bills,
            payments: billPayments
        )
    }

    func dashboardSnapshot() -> DashboardSnapshot {
        computeDashboardSnapshot()
    }

    func computeDashboardSnapshot() -> DashboardSnapshot {
        DashboardInsightsEngine.build(
            unreadMailCount: totalUnread,
            unreadChatCount: totalChatUnread,
            passwordCount: notes.filter { $0.folder == .passwords }.count,
            notesCount: notes.count,
            bills: bills,
            payments: billPayments,
            clipboardEntries: clipboardEntries
        )
    }

    func persistDashboardAnalysis() {
        let stored = StoredDashboardAnalysis(
            snapshot: computeDashboardSnapshot(),
            analyzedAt: Date()
        )
        let context = ModelContext(modelContainer)
        try? DashboardAnalysisRepository.upsert(stored, context: context)
        storedDashboardAnalysis = stored
        dashboardAnalyzedAt = stored.analyzedAt
        refreshDashboardQuoteForCurrentContext(forceNew: true)
        refreshDashboardQuoteEmojis()
        refreshClipboardDayAnalysis(force: true)
    }

    func refreshClipboardDayAnalysisIfNeeded() {
        refreshClipboardDayAnalysis(force: false)
    }

    func refreshClipboardDayAnalysis(force: Bool = false) {
        let snapshot = computeDashboardSnapshot()
        let entries = clipboardEntries
        let lastAnalyzedAt = clipboardDayAnalysis?.analyzedAt
            ?? DashboardClipboardDayAnalysisService.cachedAnalysis()?.analyzedAt

        if !DashboardClipboardDayAnalysisService.shouldRefresh(
            lastAnalyzedAt: lastAnalyzedAt,
            force: force
        ) {
            if clipboardDayAnalysis == nil,
               let cached = DashboardClipboardDayAnalysisService.cachedAnalysis() {
                clipboardDayAnalysis = cached
            }
            return
        }

        clipboardDayAnalysis = DashboardClipboardDayAnalysisEngine.fallback(
            entries: entries,
            snapshot: snapshot
        )

        clipboardDayAnalysisTask?.cancel()
        clipboardDayAnalysisTask = Task { @MainActor in
            let analysis = await DashboardClipboardDayAnalysisService.resolveAnalysis(
                entries: entries,
                snapshot: snapshot,
                force: force
            )
            guard !Task.isCancelled else { return }
            clipboardDayAnalysis = analysis
        }
    }

    var nextClipboardDayAnalysisAt: Date? {
        guard let analyzedAt = clipboardDayAnalysis?.analyzedAt else { return nil }
        return analyzedAt.addingTimeInterval(DashboardClipboardDayAnalysisService.analysisInterval)
    }

    func refreshDashboardQuoteForCurrentContext(forceNew: Bool = false) {
        let isHoliday = DashboardPublicHolidayService.shared.isTodayPublicHoliday
        if forceNew {
            dashboardQuote = DashboardQuotes.pickRandom(
                excluding: dashboardQuote,
                isPublicHoliday: isHoliday
            )
            return
        }
        if let refreshed = DashboardQuotes.refreshIfContextChanged(
            excluding: dashboardQuote,
            isPublicHoliday: isHoliday
        ) {
            dashboardQuote = refreshed
        }
    }

    func refreshDashboardQuoteEmojis() {
        let quote = dashboardQuote
        if let cached = DashboardQuoteEmojiService.cachedEmojis(for: quote) {
            dashboardQuoteEmojis = cached
            return
        }

        dashboardQuoteEmojis = DashboardQuoteEmojiService.keywordEmojis(for: quote)
        dashboardQuoteEmojiTask?.cancel()
        dashboardQuoteEmojiTask = Task { @MainActor in
            let emojis = await DashboardQuoteEmojiService.resolveEmojis(for: quote)
            guard !Task.isCancelled, quote == dashboardQuote else { return }
            dashboardQuoteEmojis = emojis
        }
    }

    var nextDashboardAnalysisAt: Date? {
        guard let dashboardAnalyzedAt else { return nil }
        return dashboardAnalyzedAt.addingTimeInterval(DashboardAnalysisService.analysisInterval)
    }

    func refreshDashboardAnalysisNow() {
        DashboardAnalysisService.shared.forceAnalysis()
    }

    var hasSyncedDataToUpload: Bool {
        !notes.isEmpty
            || !activeBills.isEmpty
            || !billPayments.isEmpty
            || storedDashboardAnalysis != nil
    }

    func pushSyncedDataToCloudKit(force: Bool = true) async -> String {
        guard NucleusDatabase.usesCloudKitSync else {
            if let error = NucleusDatabase.lastCloudKitSetupError {
                return error
            }
            return "Synced data is stored on this Mac only. Sign in to iCloud and restart Nucleus."
        }

        if !hasSyncedDataToUpload {
            return "No notes, bills, or dashboard analysis to sync yet."
        }

        persistDashboardAnalysis()
        let context = ModelContext(modelContainer)
        return await syncService.queueSyncedExportAndWait { [self] in
            let counts = try NucleusDatabase.exportSyncedDataToCloudKit(context: context, force: force)
            self.reloadLocalData()
            return counts
        }
    }

    func handleIncomingURL(_ url: URL) async {
        guard url.scheme == "net.suherman.nucleus", url.host == "cloud-sync" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            return
        }

        do {
            try await cloudSyncService.handleDeepLinkToken(token)
            await completeNucleusCloudConnection()
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func connectNucleusCloud() async -> String {
        do {
            let url = try await cloudSyncService.beginConnect()
            NSWorkspace.shared.open(url)
            return "Finish authorization in your browser, then return to Nucleus."
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func completeNucleusCloudConnection() async {
        persistDashboardAnalysis()
        let context = ModelContext(modelContainer)
        await cloudSyncService.syncNow(context: context)
        reloadLocalData()
        statusMessage = "Nucleus Cloud connected"
    }

    func pushToNucleusCloud() async -> String {
        guard cloudSyncService.status.isConnected else {
            return "Connect Nucleus Cloud in Settings first."
        }

        persistDashboardAnalysis()
        let context = ModelContext(modelContainer)
        await cloudSyncService.syncNow(context: context)
        reloadLocalData()

        if let error = cloudSyncService.lastError {
            return error
        }
        return "Synced with Nucleus Cloud."
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
        markMailSignInPending(account.id)
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
        AppSettings.shared.clearChatNotificationSound(for: account.id)
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
            updateDockBadge()
            return
        }

        isMailBackgroundSyncInProgress = true
        defer { isMailBackgroundSyncInProgress = false }

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

        accumulateMailUnreadDeltas(from: mergedUnread)

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

        for account in accounts where account.authMode == .webSession {
            GmailWebView.ensureUnreadSync(accountID: account.id, email: account.email)
        }
        NotificationCenter.default.post(name: .gmailWebUnreadPollNow, object: nil)

        updateDockBadge()
        statusMessage = statusMessageForCurrentState()
    }

    func filteredClipboardEntries() -> [ClipboardEntry] {
        ClipboardSearch.rank(clipboardEntries, query: clipboardSearchQuery)
    }

    var activeBills: [Bill] {
        bills.filter { !$0.isArchived }
    }

    var selectedBill: Bill? {
        guard let selectedBillID else { return nil }
        return bills.first { $0.id == selectedBillID }
    }

    func payments(for billID: UUID) -> [BillPayment] {
        billPayments.filter { $0.billID == billID }
    }

    func averagePayment(for billID: UUID) -> Double? {
        BillScheduleCalculator.averagePaymentAmount(billID: billID, payments: billPayments)
    }

    func remainingAmount(for bill: Bill) -> Double {
        BillScheduleCalculator.remainingAmount(bill: bill, payments: billPayments)
    }

    func dueProgress(for bill: Bill) -> Double {
        BillScheduleCalculator.progressUntilDue(bill: bill, payments: billPayments)
    }

    func billMonthlySummary() -> BillMonthlySummary {
        BillScheduleCalculator.monthlySummary(
            bills: bills,
            payments: billPayments
        )
    }

    func billDisplayStatus(for bill: Bill) -> BillDisplayStatus {
        BillScheduleCalculator.displayStatus(bill: bill, payments: billPayments)
    }

    func billStatusProgress(for bill: Bill) -> Double {
        let status = billDisplayStatus(for: bill)
        return BillScheduleCalculator.statusProgress(
            bill: bill,
            payments: billPayments,
            status: status
        )
    }

    @discardableResult
    func importBillsFromCSV(_ text: String, replaceExisting: Bool = false) -> BillCSVImportResult {
        let parsed = BillCSVCodec.importCSV(text, existingBills: bills)
        let context = ModelContext(modelContainer)
        do {
            var stored = try BillRepository.importData(
                bills: parsed.bills,
                payments: parsed.payments,
                context: context,
                replaceExisting: replaceExisting
            )
            stored.errors.append(contentsOf: parsed.result.errors)
            if NucleusDatabase.usesCloudKitSync {
                _ = try NucleusDatabase.exportBillsToCloudKit(context: context, force: true)
            }
            reloadLocalData()
            statusMessage = "Imported \(stored.billsImported) bill(s) and \(stored.paymentsImported) payment(s)"
            reconcileImportedBillDueDates()
            return stored
        } catch {
            var result = parsed.result
            result.errors.append(error.localizedDescription)
            statusMessage = "Bill import failed"
            return result
        }
    }

    func exportBillsCSV() -> String {
        BillCSVCodec.exportCSV(bills: bills, payments: billPayments)
    }

    func sampleBillsCSV() -> String {
        guard let url = Bundle.main.url(forResource: "nucleus-bills-import-demo", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return BillCSVCodec.exportCSV(bills: [], payments: [])
        }
        return text
    }

    func pushBillsToCloudKit(force: Bool = true) async -> String {
        guard NucleusDatabase.usesCloudKitSync else {
            if let error = NucleusDatabase.lastCloudKitSetupError {
                return error
            }
            return "Bills are stored on this Mac only. Sign in to iCloud and restart Nucleus."
        }

        if bills.isEmpty, billPayments.isEmpty {
            return "No bills or payments to upload."
        }

        let context = ModelContext(modelContainer)
        return await syncService.queueBillsExportAndWait { [self] in
            let count = try NucleusDatabase.exportBillsToCloudKit(context: context, force: force)
            self.reloadLocalData()
            return count
        }
    }

    func saveBill(_ bill: Bill) {
        let context = ModelContext(modelContainer)
        try? BillRepository.upsert(bill, context: context)
        if NucleusDatabase.usesCloudKitSync {
            try? NucleusDatabase.exportBillsToCloudKit(context: context, force: true)
        }
        reloadLocalData()
        selectedBillID = bill.id
        persistDashboardAnalysis()
        statusMessage = "Saved bill"
    }

    private func reconcileImportedBillDueDates() {
        var updatedBills = bills
        BillScheduleCalculator.reconcileFullyPaidBills(bills: &updatedBills, payments: billPayments)
        let context = ModelContext(modelContainer)
        for bill in updatedBills {
            if let original = bills.first(where: { $0.id == bill.id }), original.nextDueDate != bill.nextDueDate {
                try? BillRepository.upsert(bill, context: context)
            }
        }
        reloadLocalData()
        persistDashboardAnalysis()
    }

    func deleteBill(id: UUID) {
        let context = ModelContext(modelContainer)
        try? BillRepository.delete(id: id, context: context)
        if NucleusDatabase.usesCloudKitSync {
            try? NucleusDatabase.exportBillsToCloudKit(context: context, force: true)
        }
        reloadLocalData()
        persistDashboardAnalysis()
        statusMessage = "Deleted bill"
    }

    func logBillPayment(billID: UUID, amount: Double, note: String = "") {
        guard var bill = bills.first(where: { $0.id == billID }) else { return }

        let payment = BillPayment(billID: billID, amount: amount, note: note)
        let context = ModelContext(modelContainer)
        try? BillRepository.insertPayment(payment, context: context)

        let remaining = BillScheduleCalculator.remainingAmount(
            bill: bill,
            payments: billPayments + [payment]
        )
        if remaining <= 0.009 {
            bill.nextDueDate = BillScheduleCalculator.advanceDueDate(
                from: bill.nextDueDate,
                recurrence: bill.recurrence,
                customIntervalDays: bill.customIntervalDays
            )
            try? BillRepository.upsert(bill, context: context)
        }

        if NucleusDatabase.usesCloudKitSync {
            try? NucleusDatabase.exportBillsToCloudKit(context: context, force: true)
        }

        reloadLocalData()
        persistDashboardAnalysis()
        statusMessage = "Logged payment"
    }

    func toggleClipboardPin(_ entry: ClipboardEntry) {
        let context = ModelContext(modelContainer)
        let pinning = !entry.isPinned
        try? ClipboardRepository.setPinned(id: entry.id, pinned: pinning, context: context)
        reloadLocalData()
    }

    func dismissClipboardPasswordSuggestion() {
        if let suggestion = clipboardPasswordSuggestion {
            rememberDismissedPasswordSuggestion(suggestion.password)
            NucleusNotificationService.shared.clearPasswordNotification(entryID: suggestion.id)
        }
        clipboardPasswordSuggestion = nil
    }

    func acceptClipboardPasswordSuggestion() async {
        guard let suggestion = clipboardPasswordSuggestion else { return }
        NucleusNotificationService.shared.clearPasswordNotification(entryID: suggestion.id)
        clipboardPasswordSuggestion = nil
        rememberDismissedPasswordSuggestion(suggestion.password)
        await createPasswordNoteFromClipboard(
            password: suggestion.password,
            source: suggestion.sourceApplication
        )
    }

    func createPasswordNoteFromClipboard(password: String, source: String) async {
        let fields = PasswordNoteFields.fromDetectedPassword(password, source: source)
        let note = NoteDocument(
            title: fields.name,
            markdown: fields.markdown(),
            folder: .passwords
        )
        sidebarSelection = .workspace(.notes)
        await saveNote(note, selectNote: true)
        statusMessage = "Password note created — fill in the details"
    }

    func saveClipboardToNote(_ entry: ClipboardEntry, selectNote: Bool = true) async {
        let note = NoteDocument(
            title: "Clipboard \(NucleusFormatters.time.string(from: entry.capturedAt))",
            markdown: NotesMarkdown.clipboardNoteTemplate(
                from: entry.content,
                source: entry.sourceApplication,
                capturedAt: entry.capturedAt
            ),
            folder: .notes
        )
        await saveNote(note, selectNote: selectNote)
    }

    func deleteNote(_ note: NoteDocument) async {
        let context = ModelContext(modelContainer)
        try? NoteRepository.delete(id: note.id, context: context)
        syncService.markNotesLocalChange()
        reloadLocalData()
        if selectedNoteID == note.id {
            selectedNoteID = notes.first?.id
        }
        statusMessage = "Deleted note"
    }

    func moveNote(_ note: NoteDocument, to folder: NoteFolder) async {
        guard note.folder != folder else { return }

        var updated = note
        updated.folder = folder

        if folder == .passwords, !note.folder.isSensitive {
            let parsed = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
            updated.markdown = parsed.markdown()
            updated.title = NotesMarkdown.title(from: updated.markdown, fallback: note.title)
        }

        await saveNote(updated, selectNote: true)
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
        syncService.markNotesLocalChange()
        reloadLocalData()
        if selectNote {
            selectedNoteID = updated.id
        }
    }

    func pushNotesToCloudKit(force: Bool = true) async -> String {
        guard NucleusDatabase.usesCloudKitSync else {
            if let error = NucleusDatabase.lastCloudKitSetupError {
                return error
            }
            return "Notes are stored on this Mac only. Sign in to iCloud and restart Nucleus."
        }

        if notes.isEmpty {
            return "No notes to upload."
        }

        let context = ModelContext(modelContainer)
        return await syncService.queueNotesExportAndWait { [self] in
            let count = try NucleusDatabase.exportNotesToCloudKit(context: context, force: force)
            self.reloadLocalData()
            return count
        }
    }

    func createNote(in folder: NoteFolder) async {
        let note: NoteDocument
        if folder == .passwords {
            let title = "New Entry"
            note = NoteDocument(
                title: title,
                markdown: NotesMarkdown.passwordNoteTemplate(title: title),
                folder: .passwords
            )
        } else {
            note = NoteDocument(
                title: "Untitled",
                markdown: NotesMarkdown.generalNoteTemplate(title: "Untitled"),
                folder: .notes
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
        let entry = capture.asEntry()
        let context = ModelContext(modelContainer)
        try? ClipboardRepository.insert(entry, context: context)
        reloadLocalData()
        evaluateClipboardForPassword(entry: entry, capture: capture)
    }

    private func evaluateClipboardForPassword(entry: ClipboardEntry, capture: ClipboardCapture) {
        guard AppSettings.shared.clipboardPasswordDetectionEnabled else { return }
        guard !isNucleusSourceApplication(capture.sourceApplication) else { return }
        guard let analysis = ClipboardPasswordAnalyzer.analyze(capture.content) else { return }

        let hash = passwordSuggestionHash(for: analysis.extractedPassword)
        guard !dismissedPasswordSuggestionHashes.contains(hash) else { return }
        guard clipboardPasswordSuggestion?.password != analysis.extractedPassword else { return }

        let suggestion = ClipboardPasswordSuggestion(
            id: entry.id,
            password: analysis.extractedPassword,
            sourceApplication: capture.sourceApplication,
            capturedAt: capture.capturedAt,
            reason: analysis.reason
        )
        clipboardPasswordSuggestion = suggestion
        NucleusNotificationService.shared.notifyClipboardPasswordSuggestion(suggestion)
    }

    private func handleClipboardPasswordNotificationAction(
        _ action: NucleusNotificationService.ClipboardPasswordAction
    ) {
        switch action {
        case .show(let entryID), .save(let entryID):
            MenuBarStatusItemController.shared.showPasswordSavePopover(entryID: entryID)
        case .dismiss(let entryID):
            menuBarController.dismissPasswordSuggestion(entryID: entryID)
        }
    }

    private func isNucleusSourceApplication(_ source: String) -> Bool {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Nucleus"
        return source.localizedCaseInsensitiveContains(appName)
            || source.localizedCaseInsensitiveContains("Nucleus")
    }

    private func rememberDismissedPasswordSuggestion(_ password: String) {
        dismissedPasswordSuggestionHashes.insert(passwordSuggestionHash(for: password))
    }

    private func passwordSuggestionHash(for password: String) -> String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
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
