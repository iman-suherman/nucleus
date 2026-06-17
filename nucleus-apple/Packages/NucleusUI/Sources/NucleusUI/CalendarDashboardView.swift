import NucleusCore
import SwiftUI

public struct CalendarEventRow: View {
    let event: CalendarEventSummary

    public init(event: CalendarEventSummary) {
        self.event = event
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(NucleusFormatters.time.string(from: event.startDate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(NucleusFormatters.time.string(from: event.endDate))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 56, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let link = event.meetingLink, let url = URL(string: link) {
                    Link("Join meeting", destination: url)
                        .font(.subheadline)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

public struct CalendarDashboardView: View {
    let events: [CalendarEventSummary]
    let isSyncing: Bool
    let onRefresh: () -> Void

    public init(
        events: [CalendarEventSummary],
        isSyncing: Bool,
        onRefresh: @escaping () -> Void
    ) {
        self.events = events
        self.isSyncing = isSyncing
        self.onRefresh = onRefresh
    }

    public var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView(
                    "No upcoming events",
                    systemImage: "calendar",
                    description: Text("Pull to refresh after signing into Calendar.")
                )
            } else {
                ForEach(events) { event in
                    CalendarEventRow(event: event)
                }
            }
        }
        .overlay(alignment: .top) {
            if isSyncing {
                ProgressView()
                    .padding(.top, 8)
            }
        }
        .refreshable {
            onRefresh()
        }
    }
}

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
