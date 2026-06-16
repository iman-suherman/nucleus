import NotesKit
import NucleusKit
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var controller: MenuBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let suggestion = controller.pendingSuggestion {
                passwordPromptSection(suggestion)
                Divider()
            }

            HStack(alignment: .top, spacing: 0) {
                clipboardSection
                    .frame(maxWidth: .infinity)
                Divider()
                passwordsSection
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 360)
        }
        .frame(width: 680)
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent clipboard", systemImage: "doc.on.clipboard")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if controller.clipboardEntries.isEmpty {
                Text("Copy something to begin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.clipboardEntries) { entry in
                            Button {
                                controller.copyEntry(entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.content)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text("\(entry.sourceApplication) · \(entry.capturedAt, style: .relative)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var passwordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Passwords", systemImage: "key.fill")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if controller.passwordNotes.isEmpty {
                Text("Saved passwords appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.passwordNotes) { note in
                            passwordRow(note)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func passwordRow(_ note: NoteDocument) -> some View {
        let fields = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
        return VStack(alignment: .leading, spacing: 6) {
            Text(fields.name.isEmpty ? note.title : fields.name)
                .font(.subheadline.weight(.semibold))
            if !fields.username.isEmpty {
                Text(fields.username)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !fields.url.isEmpty {
                Text(fields.url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button("Copy username") { controller.copyUsername(note) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(fields.username.isEmpty)
                    Button("Copy password") { controller.copyPassword(note) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(fields.password.isEmpty)
                }
                Button("Open URL") { controller.openPasswordURL(note) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(fields.url.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func passwordPromptSection(_ suggestion: ClipboardPasswordSuggestionPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Save to Passwords?", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("Detected from \(suggestion.sourceApplication). \(suggestion.reason)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Title", text: $controller.passwordDraftName)
            TextField("URL", text: $controller.passwordDraftURL)
            TextField("Username", text: $controller.passwordDraftUsername)
            TextField("Email", text: $controller.passwordDraftEmail)

            HStack {
                Button("Not Now") { controller.dismissSuggestion() }
                Spacer()
                Button("Save") { controller.saveSuggestion() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08))
    }
}
