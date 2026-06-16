import DatabaseKit
import Foundation
import SwiftData

/// One-time cleanup when clipboard clips no longer auto-create notes.
@MainActor
enum NotesClipboardMigration {
    private static let completedKey = "nucleus.migration.notesClipboardManualOnly.v1"

    static func resetNotesForClipboardPolicyChange(modelContainer: ModelContainer) -> Bool {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return false }

        let context = ModelContext(modelContainer)
        try? NoteRepository.deleteAll(context: context)
        UserDefaults.standard.removeObject(forKey: "NucleusCloudKitNotesExportedToCloudKit")

        AppSettings.shared.clipboardSaveToNotesEnabled = false

        UserDefaults.standard.set(true, forKey: completedKey)
        return true
    }
}
