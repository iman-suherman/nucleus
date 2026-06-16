import Combine
import DatabaseKit
import Foundation
import NucleusKit
import SwiftData
import SyncKit

@MainActor
protocol SyncedLayoutApplying: AnyObject {
    func applySyncedLayout(from settings: AppSettings)
}

@MainActor
final class SettingsSyncBridge {
    static let shared = SettingsSyncBridge()

    private var modelContainer: ModelContainer?
    private weak var layoutDelegate: SyncedLayoutApplying?
    private var settingsObserver: AnyCancellable?
    private var remoteChangeObserver: AnyCancellable?
    private var isApplyingRemote = false
    private var pushTask: Task<Void, Never>?
    private var lastAppliedRemoteUpdatedAt: Date = .distantPast
    private var lastLocalPushAt: Date = .distantPast

    private init() {}

    func start(
        modelContainer: ModelContainer,
        settings: AppSettings,
        layoutDelegate: SyncedLayoutApplying?
    ) {
        self.modelContainer = modelContainer
        self.layoutDelegate = layoutDelegate
        mergeOnLaunch(into: settings)
        observeSettingsChanges(settings)
        observeRemoteChanges(settings)
    }

    func pushNow(from settings: AppSettings) {
        guard let modelContainer else { return }
        guard !isApplyingRemote else { return }

        let context = ModelContext(modelContainer)
        let configuration = makeConfiguration(from: settings, context: context)
        try? SyncedSettingsRepository.upsert(configuration, context: context)
        lastLocalPushAt = configuration.updatedAt
    }

    func applyRemote(into settings: AppSettings) {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        guard let remote = try? SyncedSettingsRepository.fetch(context: context) else { return }

        guard remote.updatedAt > lastAppliedRemoteUpdatedAt else { return }

        // Ignore CloudKit echo notifications immediately after this device pushed.
        if remote.updatedAt <= lastLocalPushAt,
           Date().timeIntervalSince(lastLocalPushAt) < 2 {
            return
        }

        lastAppliedRemoteUpdatedAt = remote.updatedAt
        isApplyingRemote = true
        settings.apply(remoteConfiguration: remote)
        layoutDelegate?.applySyncedLayout(from: settings)
        isApplyingRemote = false
    }

    private func mergeOnLaunch(into settings: AppSettings) {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let localConfiguration = makeConfiguration(from: settings, context: context)

        if let remote = try? SyncedSettingsRepository.fetch(context: context) {
            if remote.updatedAt >= localConfiguration.updatedAt {
                isApplyingRemote = true
                settings.apply(remoteConfiguration: remote)
                layoutDelegate?.applySyncedLayout(from: settings)
                isApplyingRemote = false
                lastAppliedRemoteUpdatedAt = remote.updatedAt
            } else if !CloudKitStoreMigration.didResetThisLaunch {
                try? SyncedSettingsRepository.upsert(localConfiguration, context: context)
                lastLocalPushAt = localConfiguration.updatedAt
            }
            return
        }

        guard !CloudKitStoreMigration.didResetThisLaunch else { return }

        try? SyncedSettingsRepository.upsert(localConfiguration, context: context)
        lastLocalPushAt = localConfiguration.updatedAt
        layoutDelegate?.applySyncedLayout(from: settings)
    }

    private func observeSettingsChanges(_ settings: AppSettings) {
        settingsObserver = settings.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self, weak settings] _ in
                guard let self, let settings else { return }
                self.schedulePush(from: settings)
            }
    }

    private func observeRemoteChanges(_ settings: AppSettings) {
        remoteChangeObserver = NotificationCenter.default.publisher(for: .nucleusCloudKitDataDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak settings] _ in
                guard let self, let settings else { return }
                self.applyRemote(into: settings)
            }
    }

    private func schedulePush(from settings: AppSettings) {
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            pushNow(from: settings)
        }
    }

    private func makeConfiguration(from settings: AppSettings, context: ModelContext) -> NucleusSyncedConfiguration {
        let accounts = (try? AccountRepository.fetchAll(context: context)) ?? []
        let primaryAccountID = accounts.first(where: { $0.isPrimary })?.id.uuidString
        let overrides = Dictionary(
            uniqueKeysWithValues: settings.mailNotificationSoundOverrides.map { ($0.key.uuidString, $0.value.rawValue) }
        )
        let chatOverrides = Dictionary(
            uniqueKeysWithValues: settings.chatNotificationSoundOverrides.map { ($0.key.uuidString, $0.value.rawValue) }
        )

        return NucleusSyncedConfiguration(
            version: NucleusSyncedConfiguration.currentVersion,
            primaryAccountID: primaryAccountID,
            mailSyncInterval: settings.mailSyncInterval,
            mailNotificationSound: settings.mailNotificationSound.rawValue,
            mailNotificationSoundByAccount: overrides,
            chatNotificationSound: settings.chatNotificationSound.rawValue,
            chatNotificationSoundByAccount: chatOverrides,
            emailNotificationsEnabled: settings.emailNotificationsEnabled,
            chatNotificationsEnabled: settings.chatNotificationsEnabled,
            calendarNotificationsEnabled: settings.calendarNotificationsEnabled,
            selectedWorkspacePane: settings.selectedWorkspacePane,
            windowLayout: settings.windowLayout?.cloudKitColumnWidths(),
            clipboardSyncEnabled: settings.clipboardSyncEnabled,
            clipboardSaveToNotesEnabled: settings.clipboardSaveToNotesEnabled,
            iCloudKeychainTokenSyncEnabled: settings.iCloudKeychainTokenSyncEnabled,
            billNotificationsEnabled: settings.billNotificationsEnabled,
            billNotificationHour: settings.billNotificationHour,
            billNotifySevenDaysBefore: settings.billNotifySevenDaysBefore,
            billNotifyThreeDaysBefore: settings.billNotifyThreeDaysBefore,
            billNotifyOneDayBefore: settings.billNotifyOneDayBefore,
            billNotifyOnDueDate: settings.billNotifyOnDueDate,
            updatedAt: Date()
        )
    }
}

extension AppSettings {
    func apply(remoteConfiguration: NucleusSyncedConfiguration) {
        mailSyncInterval = remoteConfiguration.mailSyncInterval

        if let raw = MailNotificationSound(rawValue: remoteConfiguration.mailNotificationSound) {
            mailNotificationSound = raw
        }

        var overrides: [UUID: MailNotificationSound] = [:]
        for (accountIDRaw, soundRaw) in remoteConfiguration.mailNotificationSoundByAccount {
            guard let accountID = UUID(uuidString: accountIDRaw),
                  let sound = MailNotificationSound(rawValue: soundRaw) else { continue }
            overrides[accountID] = sound
        }
        replaceMailNotificationSoundOverrides(overrides)

        if let raw = ChatNotificationSound(rawValue: remoteConfiguration.chatNotificationSound) {
            chatNotificationSound = raw
        }

        var chatOverrides: [UUID: ChatNotificationSound] = [:]
        for (accountIDRaw, soundRaw) in remoteConfiguration.chatNotificationSoundByAccount {
            guard let accountID = UUID(uuidString: accountIDRaw),
                  let sound = ChatNotificationSound(rawValue: soundRaw) else { continue }
            chatOverrides[accountID] = sound
        }
        replaceChatNotificationSoundOverrides(chatOverrides)

        // Selected inbox/calendar/chat tabs stay on this Mac only.
        emailNotificationsEnabled = remoteConfiguration.emailNotificationsEnabled
        chatNotificationsEnabled = remoteConfiguration.chatNotificationsEnabled
        calendarNotificationsEnabled = remoteConfiguration.calendarNotificationsEnabled
        selectedWorkspacePane = remoteConfiguration.selectedWorkspacePane
        if let remoteLayout = remoteConfiguration.windowLayout {
            var layout = windowLayout ?? WindowLayoutState(width: 1320, height: 880)
            layout.mergeCloudKitColumnWidths(from: remoteLayout)
            windowLayout = layout
        }
        clipboardSyncEnabled = remoteConfiguration.clipboardSyncEnabled
        clipboardSaveToNotesEnabled = remoteConfiguration.clipboardSaveToNotesEnabled
        iCloudKeychainTokenSyncEnabled = remoteConfiguration.iCloudKeychainTokenSyncEnabled
        billNotificationsEnabled = remoteConfiguration.billNotificationsEnabled
        billNotificationHour = remoteConfiguration.billNotificationHour
        billNotifySevenDaysBefore = remoteConfiguration.billNotifySevenDaysBefore
        billNotifyThreeDaysBefore = remoteConfiguration.billNotifyThreeDaysBefore
        billNotifyOneDayBefore = remoteConfiguration.billNotifyOneDayBefore
        billNotifyOnDueDate = remoteConfiguration.billNotifyOnDueDate
    }
}
