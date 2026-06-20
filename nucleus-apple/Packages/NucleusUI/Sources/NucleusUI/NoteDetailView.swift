import NucleusCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum NoteSaveStatus: Equatable {
    case idle
    case saving
    case saved
}

private struct NoteEditorSnapshot: Equatable {
    var markdown: String
    var title: String
    var folder: NoteFolder
}

private struct NoteSaveStatusIndicator: View {
    let status: NoteSaveStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .saving:
            HStack(spacing: 4) {
                ProgressView()
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Saving")
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Saved")
        }
    }
}

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
    @State private var saveStatus: NoteSaveStatus = .idle
    @State private var savedSnapshot: NoteEditorSnapshot?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var savedIndicatorTask: Task<Void, Never>?

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
                NoteSaveStatusIndicator(status: saveStatus)
            }
        }
        .onAppear {
            savedSnapshot = currentSnapshot()
        }
        .onChange(of: editorText) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: passwordFields) { _, _ in
            scheduleAutoSave()
        }
        .onDisappear {
            flushAutoSave()
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

    private var isDirty: Bool {
        guard let savedSnapshot else { return true }
        return currentSnapshot() != savedSnapshot
    }

    private func currentSnapshot() -> NoteEditorSnapshot {
        if folder == .passwords {
            let markdown = passwordFields.markdown()
            let title = passwordFields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? note.title
                : passwordFields.name
            return NoteEditorSnapshot(markdown: markdown, title: title, folder: folder)
        }

        let title = NotesMarkdown.title(from: editorText, fallback: note.title)
        let markdown = NotesMarkdown.settingTitle(title, in: editorText)
        return NoteEditorSnapshot(markdown: markdown, title: title, folder: folder)
    }

    private func buildUpdatedNote() -> NoteDocument {
        var updated = note
        let snapshot = currentSnapshot()
        updated.folder = snapshot.folder
        updated.markdown = snapshot.markdown
        updated.title = snapshot.title
        updated.updatedAt = Date()
        return updated
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard isDirty else { return }

        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, isDirty else { return }
            await performSave()
        }
    }

    private func flushAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        guard isDirty else { return }
        saveNote()
    }

    @MainActor
    private func performSave() async {
        saveNote()
    }

    private func saveNote() {
        guard isDirty else { return }

        let updated = buildUpdatedNote()
        saveStatus = .saving

        do {
            try onSave(updated)
            savedSnapshot = currentSnapshot()
            markSaved()
        } catch {
            saveStatus = .idle
            saveError = error.localizedDescription
        }
    }

    private func markSaved() {
        saveStatus = .saved
        savedIndicatorTask?.cancel()
        savedIndicatorTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if saveStatus == .saved {
                saveStatus = .idle
            }
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
