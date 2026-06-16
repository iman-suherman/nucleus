import CloudKit
import Foundation

enum CloudKitRecordDiagnostics {
    static let syncedRecordTypes = [
        "CD_NoteRecord",
        "CD_GoogleAccountRecord",
        "CD_SyncedSettingsRecord",
        "CD_ClipboardItemRecord",
    ]

    static let productionSchemaHint =
        "Open CloudKit Console → iCloud.net.suherman.nucleus → Schema → Production. "
        + "Import cloudkit/nucleus-development.ckdb into Development, then Deploy Schema Changes to Production."

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
}
