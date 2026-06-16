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

    enum ProbeWriteOutcome: Sendable {
        case success(String)
        case failure(String)
    }

    /// Writes and deletes a minimal note record to distinguish schema/quota issues from local export queue problems.
    static func probeNoteRecordWrite(
        containerID: String,
        zoneName: String
    ) async -> ProbeWriteOutcome {
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(
            recordName: "nucleus-export-probe-\(UUID().uuidString.lowercased())",
            zoneID: zoneID
        )
        let record = CKRecord(recordType: "CD_NoteRecord", recordID: recordID)
        record["CD_id"] = UUID().uuidString as CKRecordValue
        record["CD_title"] = "Nucleus export probe" as CKRecordValue
        record["CD_markdown"] = "" as CKRecordValue
        record["CD_folderRaw"] = "notes" as CKRecordValue
        record["CD_updatedAt"] = Date() as CKRecordValue

        do {
            let saved = try await database.save(record)
            _ = try await database.deleteRecord(withID: saved.recordID)
            return .success("CloudKit accepted a test CD_NoteRecord write — Production schema and permissions look OK.")
        } catch {
            return .failure(CloudKitErrorDescriber.describe(error))
        }
    }
}
