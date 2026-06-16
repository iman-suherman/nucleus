import NotesKit
import NucleusKit
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var controller: MenuBarController
    @State private var isEditingPasswordVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let suggestion = controller.pendingSuggestion {
                passwordPromptSection(suggestion)
                Divider()
            }

            if controller.isEditingPassword {
                passwordEditSection
                Divider()
            }

            HStack(alignment: .top, spacing: 0) {
                clipboardSection
                    .frame(maxWidth: .infinity)
                Divider()
                passwordsSection
                    .frame(maxWidth: .infinity)
            }
            .frame(height: contentHeight)
        }
        .frame(width: 680)
        .confirmationDialog(
            "Delete this password?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                controller.confirmDeletePassword()
            }
            Button("Cancel", role: .cancel) {
                controller.cancelDeletePassword()
            }
        } message: {
            if let note = pendingDeletionNote {
                Text("“\(PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title).name)” will be removed from Passwords.")
            }
        }
        .onChange(of: controller.editingPasswordID) { _, newValue in
            if newValue == nil {
                isEditingPasswordVisible = false
            }
        }
    }

    private var contentHeight: CGFloat {
        if controller.pendingSuggestion != nil || controller.isEditingPassword {
            return 300
        }
        return 360
    }

    private var pendingDeletionNote: NoteDocument? {
        guard let id = controller.passwordPendingDeletionID else { return nil }
        return controller.passwordNote(for: id)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { controller.passwordPendingDeletionID != nil },
            set: { isPresented in
                if !isPresented {
                    controller.cancelDeletePassword()
                }
            }
        )
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
        let isEditing = controller.editingPasswordID == note.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(fields.name.isEmpty ? note.title : fields.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isEditing {
                    Text("Editing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            if !fields.username.isEmpty {
                Text(fields.username)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !fields.email.isEmpty {
                Text(fields.email)
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
                    Button("Copy email") { controller.copyEmail(note) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(fields.email.isEmpty)
                }
                HStack(spacing: 6) {
                    Button("Copy password") { controller.copyPassword(note) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(fields.password.isEmpty)
                    Button("Open URL") { controller.openPasswordURL(note) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(fields.url.isEmpty)
                }
                HStack(spacing: 6) {
                    Button(isEditing ? "Editing…" : "Edit") {
                        controller.beginEditingPassword(note)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isEditing)

                    Button("Delete", role: .destructive) {
                        controller.requestDeletePassword(note)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isEditing ? Color.orange.opacity(0.08) : Color.clear)
    }

    private var passwordEditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Edit password", systemImage: "pencil")
                .font(.headline)

            TextField("Title", text: $controller.editingDraftName)
            TextField("URL", text: $controller.editingDraftURL)
            TextField("Username", text: $controller.editingDraftUsername)
            TextField("Email", text: $controller.editingDraftEmail)

            HStack(spacing: 8) {
                Group {
                    if isEditingPasswordVisible {
                        TextField("Password", text: $controller.editingDraftPassword)
                    } else {
                        SecureField("Password", text: $controller.editingDraftPassword)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button(isEditingPasswordVisible ? "Hide" : "Show") {
                    isEditingPasswordVisible.toggle()
                }
                .controlSize(.small)
            }

            HStack {
                Button("Cancel") { controller.cancelEditingPassword() }
                Spacer()
                Button("Save") { controller.saveEditedPassword() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.editingDraftPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
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
