import CloudKit
import Foundation

enum CloudKitRecordDiagnostics {
    static let syncedRecordTypes = [
        "CD_NoteRecord",
        "CD_GoogleAccountRecord",
        "CD_SyncedSettingsRecord",
        "CD_ClipboardItemRecord",
        "CD_BillRecord",
        "CD_BillPaymentRecord",
        "CD_DashboardAnalysisRecord",
        "CD_CalendarEventRecord",
    ]

    static let productionSchemaDeployHint =
        "Deploy updated schema in CloudKit Console → iCloud.net.suherman.nucleus → Development → Deploy Schema Changes → Production (must include CD_entityName on all CD_* record types)."

    static let productionSchemaHint = productionSchemaDeployHint

    static func countRecords(
        containerID: String,
        zoneName: String,
        recordType: String
    ) async -> Result<Int, Error> {
        let container = CKContainer(identifier: containerID)
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let query = CKQuery(
            recordType: recordType,
            predicate: NSPredicate(format: "CD_id != %@", "")
        )

        do {
            let (results, _) = try await container.privateCloudDatabase.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: []
            )
            return .success(results.count)
        } catch {
            return .failure(error)
        }
    }

    static func summarizeRemoteCounts(
        containerID: String,
        zoneName: String
    ) async -> String {
        var parts: [String] = []
        for recordType in syncedRecordTypes {
            switch await countRecords(containerID: containerID, zoneName: zoneName, recordType: recordType) {
            case .success(let count):
                parts.append("\(recordType)=\(count)")
            case .failure(let error):
                parts.append("\(recordType)=? (\(CloudKitErrorDescriber.describe(error)))")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// Read-only check: record types that fail to query likely need a Production schema deploy.
    static func validateSyncedRecordTypesReadable(
        containerID: String,
        zoneName: String
    ) async -> String {
        var parts: [String] = []
        for recordType in syncedRecordTypes {
            switch await countRecords(containerID: containerID, zoneName: zoneName, recordType: recordType) {
            case .success:
                parts.append("\(recordType)=readable")
            case .failure(let error):
                parts.append("\(recordType)=unreadable (\(CloudKitErrorDescriber.describe(error)))")
            }
        }
        return parts.joined(separator: ", ")
    }
}
