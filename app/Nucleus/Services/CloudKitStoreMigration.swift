import AccountKit
import DatabaseKit
import Foundation
import SyncKit

/// One-time local store resets after incompatible SwiftData / CloudKit schema changes.
@MainActor
enum CloudKitStoreMigration {
    private static let v400Key = "nucleus.migration.cloudKitStoreReset.v400"
    private static let calendarSchemaKey = "nucleus.migration.calendarCloudKitSchema.v0112"

    private(set) static var didResetThisLaunch = false
    private(set) static var didResetCalendarSchemaThisLaunch = false

    @discardableResult
    static func resetIfNeeded() -> Bool {
        guard !UserDefaults.standard.bool(forKey: v400Key) else { return false }

        performFullReset(reason: "v0.4.0 CloudKit schema compatibility")
        UserDefaults.standard.set(true, forKey: v400Key)
        didResetThisLaunch = true
        return true
    }

    /// CalendarEventRecord must use CloudKit-compatible defaults; older 0.11.x builds could block iCloud open.
    @discardableResult
    static func resetForCalendarCloudKitSchemaIfNeeded() -> Bool {
        guard !UserDefaults.standard.bool(forKey: calendarSchemaKey) else { return false }

        resetLocalStores(reason: "calendar iCloud schema compatibility (v0.11.2)")
        UserDefaults.standard.set(true, forKey: calendarSchemaKey)
        didResetCalendarSchemaThisLaunch = true
        didResetThisLaunch = true
        return true
    }

    private static func performFullReset(reason: String) {
        resetLocalStores(reason: reason)
        KeychainTokenStore.shared.deleteAllTokens()
        AppSettings.shared.selectedMailAccountID = nil
        AppSettings.shared.selectedCalendarAccountID = nil
        AppSettings.shared.selectedChatAccountID = nil
    }

    private static func resetLocalStores(reason: String) {
        do {
            try NucleusDatabase.removeAllLocalStoreFiles()
        } catch {
            NSLog("Nucleus: failed to remove local stores during migration: %@", error.localizedDescription)
        }

        NucleusDatabase.resetCloudKitUserDefaults()
        CloudKitSyncLogStore.shared.clear()
        CloudKitSyncLogStore.shared.log(
            "Local iCloud store reset for \(reason). Re-sync from iCloud or use Settings → iCloud → Sync to iCloud.",
            level: .warning
        )
        NSLog("Nucleus: reset local database for \(reason)")
    }
}
