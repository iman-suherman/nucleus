import NucleusCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct NoteDetailView: View {
    let note: NoteDocument
    let onSave: (NoteDocument) throws -> Void
    var onDelete: ((NoteDocument) throws -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var folder: NoteFolder
    @State private var editorText: String
    @State private var passwordFields: PasswordNoteFields
    @State private var saveError: String?
    @State private var deleteError: String?
    @State private var showingDeleteConfirmation = false

    public init(
        note: NoteDocument,
        onSave: @escaping (NoteDocument) throws -> Void,
        onDelete: ((NoteDocument) throws -> Void)? = nil
    ) {
        self.note = note
        self.onSave = onSave
        self.onDelete = onDelete
        _folder = State(initialValue: note.folder)
        _editorText = State(initialValue: note.folder == .passwords ? "" : note.markdown)
        _passwordFields = State(
            initialValue: note.folder == .passwords
                ? PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
                : .empty()
        )
    }

    public var body: some View {
        Group {
            if folder == .passwords {
                PasswordNoteForm(fields: $passwordFields)
            } else {
                TextEditor(text: $editorText)
                    .font(.body.monospaced())
                    .padding(4)
            }
        }
        .navigationTitle(folder == .passwords ? passwordFields.name : NotesMarkdown.title(from: editorText, fallback: note.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDelete != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveNote()
                }
            }
        }
        .confirmationDialog(
            "Delete this \(folder == .passwords ? "password entry" : "note")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Could not save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .alert("Could not delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func saveNote() {
        var updated = note
        updated.folder = folder
        updated.updatedAt = Date()

        if folder == .passwords {
            updated.markdown = passwordFields.markdown()
            updated.title = passwordFields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? note.title
                : passwordFields.name
        } else {
            let title = NotesMarkdown.title(from: editorText, fallback: note.title)
            updated.markdown = NotesMarkdown.settingTitle(title, in: editorText)
            updated.title = title
        }

        do {
            try onSave(updated)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func deleteNote() {
        guard let onDelete else { return }
        do {
            try onDelete(note)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct PasswordNoteForm: View {
    @Binding var fields: PasswordNoteFields
    @State private var isPasswordVisible = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $fields.name)
                TextField("URL", text: $fields.url)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Username", text: $fields.username)
                    .textInputAutocapitalization(.never)
                TextField("Email", text: $fields.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }

            Section {
                if isPasswordVisible {
                    TextField("Password", text: $fields.password)
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("Password", text: $fields.password)
                }

                HStack {
                    Button(isPasswordVisible ? "Hide" : "Show") {
                        isPasswordVisible.toggle()
                    }

                    Spacer()

                    Button("Copy") {
                        copyPassword()
                    }
                    .disabled(fields.password.isEmpty)
                }
            }
        }
    }

    private func copyPassword() {
        #if canImport(UIKit)
        UIPasteboard.general.string = fields.password
        #endif
    }
}
