import NucleusCore
import SwiftUI

public struct NotesListView: View {
    let notes: [NoteDocument]
    let onSave: (NoteDocument) throws -> Void
    var onDelete: ((NoteDocument) throws -> Void)?

    public init(
        notes: [NoteDocument],
        onSave: @escaping (NoteDocument) throws -> Void,
        onDelete: ((NoteDocument) throws -> Void)? = nil
    ) {
        self.notes = notes
        self.onSave = onSave
        self.onDelete = onDelete
    }

    public var body: some View {
        List {
            ForEach(notes) { note in
                NavigationLink {
                    NoteDetailView(note: note, onSave: onSave, onDelete: onDelete)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if note.folder.isSensitive {
                                Image(systemName: note.folder.systemImage)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(displayTitle(for: note))
                                .font(.headline)
                        }
                        Text(subtitle(for: note))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if let onDelete {
                        Button(role: .destructive) {
                            try? onDelete(note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func displayTitle(for note: NoteDocument) -> String {
        if note.folder == .passwords {
            return PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title).name
        }
        return NotesMarkdown.title(from: note.markdown, fallback: note.title)
    }

    private func subtitle(for note: NoteDocument) -> String {
        if note.folder == .passwords {
            let fields = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
            if !fields.url.isEmpty { return fields.url }
            if !fields.username.isEmpty { return fields.username }
            if !fields.email.isEmpty { return fields.email }
            return "Password entry"
        }
        return note.markdown
    }
}
