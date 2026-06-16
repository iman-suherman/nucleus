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
    @Published var errorMessage: String?

    let modelContainer: ModelContainer
    let accountService: MobileAccountService
    let preferencesStore = MobilePreferencesStore.shared
    let settingsSync = MobileSettingsSyncService.shared
    let notesService: NotesMetadataService
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

        normalizeSelectedTab()
        settingsSync.start(modelContainer: modelContainer)
        CloudKitSyncService.shared.start()
        await iCloudSync.refresh()
        await requestNotificationPermission()

        observeCloudKitChanges()
        accountService.reload()
        await notesService.reloadWaitingForCloudImport()

        statusMessage = "Ready"
        isBootstrapping = false
    }

    var selectedTab: MobileWorkspaceTab {
        get { MobileWorkspaceTab.normalizedForIOS(preferencesStore.preferences.selectedTab) }
        set {
            preferencesStore.update { $0.selectedTab = MobileWorkspaceTab.normalizedForIOS(newValue) }
        }
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

    private func normalizeSelectedTab() {
        let normalized = MobileWorkspaceTab.normalizedForIOS(preferencesStore.preferences.selectedTab)
        guard normalized != preferencesStore.preferences.selectedTab else { return }
        preferencesStore.update { $0.selectedTab = normalized }
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
