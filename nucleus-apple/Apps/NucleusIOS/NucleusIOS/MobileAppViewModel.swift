import Combine
import DatabaseKit
import Foundation
import NucleusCore
import SwiftData
import SwiftUI
import SyncKit
import UserNotifications

@MainActor
final class MobileAppViewModel: ObservableObject {
    @Published var isBootstrapping = true
    @Published var statusMessage = "Starting…"
    @Published var showAddAccount = false
    @Published var errorMessage: String?

    let modelContainer: ModelContainer
    let accountService: MobileAccountService
    let preferencesStore = MobilePreferencesStore.shared
    let settingsSync = MobileSettingsSyncService.shared
    let calendarSync = CalendarSyncService()
    let notesService: NotesMetadataService
    let unreadBadge = UnreadBadgeService()
    let iCloudSync = ICloudSyncDisplayService.shared

    private var cloudKitObserver: AnyCancellable?
    private var iCloudSyncObserver: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init() {
        modelContainer = (try? NucleusDatabase.makeContainer()) ?? {
            fatalError("Failed to create Nucleus database container")
        }()
        accountService = MobileAccountService(modelContainer: modelContainer)
        notesService = NotesMetadataService(modelContainer: modelContainer)

        iCloudSyncObserver = iCloudSync.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        notesService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        isBootstrapping = true
        statusMessage = "Connecting to iCloud…"

        settingsSync.start(modelContainer: modelContainer)
        CloudKitSyncService.shared.start()
        await iCloudSync.refresh()
        MeetingReminderScheduler.shared.registerCategories()
        await requestNotificationPermission()

        observeCloudKitChanges()
        accountService.reload()
        await notesService.reloadWaitingForCloudImport()

        statusMessage = "Ready"
        isBootstrapping = false
    }

    var selectedTab: MobileWorkspaceTab {
        get { preferencesStore.preferences.selectedTab }
        set {
            preferencesStore.update { $0.selectedTab = newValue }
        }
    }

    func selectedAccountID(for surface: WebSurface) -> UUID? {
        let preferences = preferencesStore.preferences
        let raw: String?
        switch surface {
        case .mail: raw = preferences.selectedMailAccountID
        case .calendar: raw = preferences.selectedCalendarAccountID
        case .chat: raw = preferences.selectedChatAccountID
        }
        if let raw, let id = UUID(uuidString: raw) {
            return id
        }
        return accountService.primaryAccount()?.id
    }

    func selectAccount(_ account: GoogleAccount, for surface: WebSurface) {
        preferencesStore.update { preferences in
            switch surface {
            case .mail:
                preferences.selectedMailAccountID = account.id.uuidString
            case .calendar:
                preferences.selectedCalendarAccountID = account.id.uuidString
            case .chat:
                preferences.selectedChatAccountID = account.id.uuidString
            }
        }
    }

    func addAccount(email: String, displayName: String) {
        do {
            _ = try accountService.addAccount(email: email, displayName: displayName)
            showAddAccount = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCalendar() async {
        guard let account = accountService.account(for: .calendar, preferences: preferencesStore.preferences) else {
            return
        }
        let cookies = await WebSessionStore.cookies(for: account.id)
        await calendarSync.syncEvents(for: account, cookies: cookies)
    }

    func reloadAccountsAndNotes() {
        accountService.reload()
        notesService.reload()
    }

    func refreshICloudSync() async {
        await iCloudSync.refresh()
        await notesService.reloadWaitingForCloudImport()
        accountService.reload()
    }

    var primaryNotesAccountEmail: String? {
        accountService.accounts.first(where: { $0.isPrimaryNotesAccount })?.email
            ?? accountService.accounts.first?.email
    }

    private func observeCloudKitChanges() {
        cloudKitObserver = NotificationCenter.default.publisher(for: .nucleusCloudKitDataDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.accountService.reload()
                Task {
                    await self?.iCloudSync.refresh()
                    await self?.notesService.reloadWaitingForCloudImport()
                }
            }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }
}
