import DatabaseKit
import Foundation
import NucleusKit
import SwiftData

/// Notes loaded from the CloudKit-backed SwiftData store shared with macOS Nucleus.
@MainActor
public final class NotesMetadataService: ObservableObject {
    @Published public private(set) var notes: [NoteDocument] = []
    @Published public private(set) var usesCloudKitSync = false
    @Published public private(set) var syncStatusMessage = ""

    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        usesCloudKitSync = NucleusDatabase.usesCloudKitSync
        syncStatusMessage = Self.statusMessage()
        reload()
    }

    public func reload() {
        usesCloudKitSync = NucleusDatabase.usesCloudKitSync
        syncStatusMessage = Self.statusMessage()

        let context = ModelContext(modelContainer)
        notes = (try? NoteRepository.fetchAll(context: context)) ?? []
    }

    /// CloudKit import can lag behind first launch — retry briefly after remote changes.
    public func reloadWaitingForCloudImport() async {
        reload()
        guard usesCloudKitSync, notes.isEmpty else { return }

        for seconds in [2, 4, 8] {
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            reload()
            if !notes.isEmpty { break }
        }
    }

    public func captureText(_ text: String, title: String? = nil) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let noteTitle = title ?? "Captured \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
        let note = NoteDocument(
            title: noteTitle,
            markdown: trimmed,
            folder: .notes
        )

        let context = ModelContext(modelContainer)
        try NoteRepository.upsert(note, context: context)
        reload()
    }

    public func saveNote(_ note: NoteDocument) throws {
        var updated = note
        updated.updatedAt = Date()

        let context = ModelContext(modelContainer)
        try NoteRepository.upsert(updated, context: context)
        CloudKitSyncService.shared.markNotesLocalChange()
        reload()
    }

    public func deleteNote(_ note: NoteDocument) throws {
        let context = ModelContext(modelContainer)
        try NoteRepository.delete(id: note.id, context: context)
        CloudKitSyncService.shared.markNotesLocalChange()
        reload()
    }

    private static func statusMessage() -> String {
        if NucleusDatabase.usesCloudKitSync {
            return "Syncing notes via iCloud CloudKit"
        }
        if let error = NucleusDatabase.lastCloudKitSetupError {
            return error
        }
        return "Notes are stored on this device only"
    }
}
