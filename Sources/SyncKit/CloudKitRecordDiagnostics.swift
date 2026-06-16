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

    enum ProbeWriteOutcome: Sendable {
        case success(String)
        case failure(String)
    }

    static func probeAllSyncedRecordTypes(containerID: String, zoneName: String) async -> String {
        var parts: [String] = []
        for recordType in syncedRecordTypes {
            switch await probeRecordTypeWrite(containerID: containerID, zoneName: zoneName, recordType: recordType) {
            case .success:
                parts.append("\(recordType)=OK")
            case .failure(let message):
                parts.append("\(recordType)=FAILED (\(message))")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// Writes and deletes a minimal note record to distinguish schema/quota issues from local export queue problems.
    static func probeNoteRecordWrite(
        containerID: String,
        zoneName: String
    ) async -> ProbeWriteOutcome {
        await probeRecordTypeWrite(containerID: containerID, zoneName: zoneName, recordType: "CD_NoteRecord")
    }

    private static func probeRecordTypeWrite(
        containerID: String,
        zoneName: String,
        recordType: String
    ) async -> ProbeWriteOutcome {
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(
            recordName: "nucleus-probe-\(recordType)-\(UUID().uuidString.lowercased())",
            zoneID: zoneID
        )
        let record = CKRecord(recordType: recordType, recordID: recordID)
        let recordUUID = UUID().uuidString
        record["CD_id"] = recordUUID as CKRecordValue

        switch recordType {
        case "CD_NoteRecord":
            record["CD_title"] = "probe" as CKRecordValue
            record["CD_markdown"] = "" as CKRecordValue
            record["CD_folderRaw"] = "notes" as CKRecordValue
            record["CD_updatedAt"] = Date() as CKRecordValue
        case "CD_GoogleAccountRecord":
            record["CD_email"] = "probe@example.com" as CKRecordValue
            record["CD_displayName"] = "probe" as CKRecordValue
            record["CD_authMode"] = "webSession" as CKRecordValue
            record["CD_isPrimary"] = 0 as CKRecordValue
            record["CD_isPrimaryNotesAccount"] = 0 as CKRecordValue
            record["CD_sortOrder"] = 0 as CKRecordValue
            record["CD_createdAt"] = Date() as CKRecordValue
        case "CD_SyncedSettingsRecord":
            record["CD_payloadData"] = Data("{}".utf8) as CKRecordValue
            record["CD_updatedAt"] = Date() as CKRecordValue
        case "CD_ClipboardItemRecord":
            record["CD_content"] = "probe" as CKRecordValue
            record["CD_contentType"] = "text" as CKRecordValue
            record["CD_sourceApplication"] = "Nucleus" as CKRecordValue
            record["CD_isPinned"] = 0 as CKRecordValue
            record["CD_capturedAt"] = Date() as CKRecordValue
        case "CD_BillRecord":
            record["CD_name"] = "probe" as CKRecordValue
            record["CD_amount"] = 0 as CKRecordValue
            record["CD_categoryRaw"] = "other" as CKRecordValue
            record["CD_recurrenceRaw"] = "monthly" as CKRecordValue
            record["CD_nextDueDate"] = Date() as CKRecordValue
            record["CD_isArchived"] = 0 as CKRecordValue
            record["CD_createdAt"] = Date() as CKRecordValue
            record["CD_sortOrder"] = 0 as CKRecordValue
        case "CD_BillPaymentRecord":
            record["CD_billID"] = UUID().uuidString as CKRecordValue
            record["CD_amount"] = 0 as CKRecordValue
            record["CD_paidAt"] = Date() as CKRecordValue
        default:
            break
        }

        do {
            let saved = try await database.save(record)
            _ = try await database.deleteRecord(withID: saved.recordID)
            return .success(recordType)
        } catch {
            return .failure(CloudKitErrorDescriber.describe(error))
        }
    }
}
