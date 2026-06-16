import CloudKit
import DatabaseKit
import Foundation
import SwiftData

/// Removes legacy CloudKit diagnostic probe rows that were written into the SwiftData sync zone.
enum CloudKitProbeArtifactCleanup {
    private static let probeNoteTitle = "probe"
    private static let probeAccountEmail = "probe@example.com"
    private static let probeBillName = "probe"
    private static let probeClipboardContent = "probe"
    private static let probeClipboardSource = "Nucleus"

    @MainActor
    static func purgeLocalProbeArtifacts(context: ModelContext) throws -> Int {
        var removed = 0

        let noteTitle = probeNoteTitle
        let noteRecords = try context.fetch(
            FetchDescriptor<NoteRecord>(
                predicate: #Predicate { $0.title == noteTitle && $0.markdown == "" }
            )
        )
        for record in noteRecords {
            context.delete(record)
            removed += 1
        }

        let accountEmail = probeAccountEmail
        let accountRecords = try context.fetch(
            FetchDescriptor<GoogleAccountRecord>(
                predicate: #Predicate { $0.email == accountEmail }
            )
        )
        for record in accountRecords {
            context.delete(record)
            removed += 1
        }

        let billName = probeBillName
        let billRecords = try context.fetch(
            FetchDescriptor<BillRecord>(
                predicate: #Predicate { $0.name == billName && $0.amount == 0 }
            )
        )
        for record in billRecords {
            context.delete(record)
            removed += 1
        }

        let clipContent = probeClipboardContent
        let clipSource = probeClipboardSource
        let clipboardRecords = try context.fetch(
            FetchDescriptor<ClipboardItemRecord>(
                predicate: #Predicate { $0.content == clipContent && $0.sourceApplication == clipSource }
            )
        )
        for record in clipboardRecords {
            context.delete(record)
            removed += 1
        }

        if removed > 0 {
            try context.save()
        }
        return removed
    }

    static func purgeRemoteProbeArtifacts(containerID: String, zoneName: String) async -> Int {
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        let targets: [(recordType: String, predicate: NSPredicate)] = [
            ("CD_NoteRecord", NSPredicate(format: "CD_title == %@ AND CD_markdown == %@", probeNoteTitle, "")),
            ("CD_GoogleAccountRecord", NSPredicate(format: "CD_email == %@", probeAccountEmail)),
            ("CD_BillRecord", NSPredicate(format: "CD_name == %@ AND CD_amount == 0", probeBillName)),
            (
                "CD_ClipboardItemRecord",
                NSPredicate(format: "CD_content == %@ AND CD_sourceApplication == %@", probeClipboardContent, probeClipboardSource)
            ),
        ]

        var deleted = 0
        for target in targets {
            deleted += await deleteMatchingRecords(
                database: database,
                zoneID: zoneID,
                recordType: target.recordType,
                predicate: target.predicate
            )
        }
        return deleted
    }

    private static func deleteMatchingRecords(
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        recordType: String,
        predicate: NSPredicate
    ) async -> Int {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var deleted = 0

        do {
            let (results, _) = try await database.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: []
            )
            for (recordID, result) in results {
                guard case .success = result else { continue }
                do {
                    _ = try await database.deleteRecord(withID: recordID)
                    deleted += 1
                } catch {
                    continue
                }
            }
        } catch {
            return 0
        }

        return deleted
    }
}
