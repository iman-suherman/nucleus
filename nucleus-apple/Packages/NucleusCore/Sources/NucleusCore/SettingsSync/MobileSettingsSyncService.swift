import Combine
import DatabaseKit
import Foundation
import NucleusKit
import SwiftData
import SyncKit

/// Syncs notification preferences and account metadata via CloudKit (same schema as macOS).
@MainActor
public final class MobileSettingsSyncService: ObservableObject {
    public static let shared = MobileSettingsSyncService()

    @Published public private(set) var syncedConfiguration: NucleusSyncedConfiguration?
    @Published public private(set) var iCloudAvailable = false

    private var modelContainer: ModelContainer?
    private var remoteChangeObserver: AnyCancellable?
    private var isApplyingRemote = false
    private var lastAppliedRemoteUpdatedAt: Date = .distantPast
    private var lastLocalPushAt: Date = .distantPast

    private init() {}

    public func start(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        mergeOnLaunch()
        observeRemoteChanges()
    }

    public func pushNotificationPreferences(
        emailEnabled: Bool,
        chatEnabled: Bool,
        calendarEnabled: Bool,
        billConfiguration: BillDueReminderConfiguration,
        iCloudKeychainTokenSyncEnabled: Bool
    ) {
        guard let modelContainer else { return }
        guard !isApplyingRemote else { return }

        let context = ModelContext(modelContainer)
        var configuration = (try? SyncedSettingsRepository.fetch(context: context))
            ?? NucleusSyncedConfiguration(updatedAt: Date())
        configuration.emailNotificationsEnabled = emailEnabled
        configuration.chatNotificationsEnabled = chatEnabled
        configuration.calendarNotificationsEnabled = calendarEnabled
        configuration.iCloudKeychainTokenSyncEnabled = iCloudKeychainTokenSyncEnabled
        configuration.billNotificationsEnabled = billConfiguration.enabled
        configuration.billNotificationHour = billConfiguration.hour
        configuration.billNotifySevenDaysBefore = billConfiguration.notifySevenDaysBefore
        configuration.billNotifyThreeDaysBefore = billConfiguration.notifyThreeDaysBefore
        configuration.billNotifyOneDayBefore = billConfiguration.notifyOneDayBefore
        configuration.billNotifyOnDueDate = billConfiguration.notifyOnDueDate
        configuration.updatedAt = Date()

        try? SyncedSettingsRepository.upsert(configuration, context: context)
        lastLocalPushAt = configuration.updatedAt
        syncedConfiguration = configuration
    }

    private func mergeOnLaunch() {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)

        if let remote = try? SyncedSettingsRepository.fetch(context: context) {
            syncedConfiguration = remote
            lastAppliedRemoteUpdatedAt = remote.updatedAt
            return
        }

        let defaults = NucleusSyncedConfiguration(updatedAt: Date())
        try? SyncedSettingsRepository.upsert(defaults, context: context)
        syncedConfiguration = defaults
        lastLocalPushAt = defaults.updatedAt
    }

    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.publisher(for: .nucleusCloudKitDataDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyRemoteIfNeeded()
            }
    }

    private func applyRemoteIfNeeded() {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        guard let remote = try? SyncedSettingsRepository.fetch(context: context) else { return }
        guard remote.updatedAt > lastAppliedRemoteUpdatedAt else { return }

        if remote.updatedAt <= lastLocalPushAt,
           Date().timeIntervalSince(lastLocalPushAt) < 2 {
            return
        }

        lastAppliedRemoteUpdatedAt = remote.updatedAt
        isApplyingRemote = true
        syncedConfiguration = remote
        isApplyingRemote = false
    }
}
