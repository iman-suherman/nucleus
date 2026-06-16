import AccountKit
import DatabaseKit
import Foundation
import SyncKit

/// One-time reset for v0.4.0 after incompatible CloudKit / SwiftData local metadata.
@MainActor
enum CloudKitStoreMigration {
    private static let completedKey = "nucleus.migration.cloudKitStoreReset.v400"

    private(set) static var didResetThisLaunch = false

    @discardableResult
    static func resetIfNeeded() -> Bool {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return false }

        do {
            try NucleusDatabase.removeAllLocalStoreFiles()
        } catch {
            NSLog("Nucleus: failed to remove local stores during v0.4.0 migration: %@", error.localizedDescription)
        }

        NucleusDatabase.resetCloudKitUserDefaults()
        KeychainTokenStore.shared.deleteAllTokens()
        CloudKitSyncLogStore.shared.clear()

        AppSettings.shared.selectedMailAccountID = nil
        AppSettings.shared.selectedCalendarAccountID = nil
        AppSettings.shared.selectedChatAccountID = nil

        UserDefaults.standard.set(true, forKey: completedKey)
        didResetThisLaunch = true
        NSLog("Nucleus: reset local database for CloudKit schema compatibility (v0.4.0)")
        return true
    }
}
