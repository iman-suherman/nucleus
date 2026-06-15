import AppKit
import NotesKit
import NucleusKit
import SwiftUI

struct NotesWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @State private var editorText = ""
    @State private var passwordFields = PasswordNoteFields.empty()
    @State private var listFilter: NoteFolder?

    var body: some View {
        HSplitView {
            notesList
                .frame(minWidth: 240, idealWidth: appSettings.notesListWidth, maxWidth: 340)

            noteEditor
                .frame(minWidth: 420)
        }
        .onAppear(perform: loadSelectedNote)
        .onChange(of: viewModel.selectedNoteID) { _, _ in
            loadSelectedNote()
        }
        .onChange(of: editorText) { _, newText in
            syncTitleFromMarkdown(newText)
        }
        .onChange(of: passwordFields.name) { _, newName in
            syncTitleFromPasswordName(newName)
        }
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                Menu("New") {
                    Button {
                        Task { await viewModel.createNote(in: .notes) }
                    } label: {
                        Label(NoteFolder.notes.rawValue, systemImage: NoteFolder.notes.systemImage)
                    }
                    Button {
                        Task { await viewModel.createNote(in: .passwords) }
                    } label: {
                        Label(NoteFolder.passwords.rawValue, systemImage: NoteFolder.passwords.systemImage)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Picker("Organize", selection: $listFilter) {
                Text("All").tag(Optional<NoteFolder>.none)
                Text(NoteFolder.notes.rawValue).tag(Optional(NoteFolder.notes))
                Text(NoteFolder.passwords.rawValue).tag(Optional(NoteFolder.passwords))
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            List(selection: $viewModel.selectedNoteID) {
                ForEach(filteredNotes) { note in
                    noteRow(for: note)
                        .tag(Optional(note.id))
                        .contextMenu {
                            noteContextMenu(for: note)
                        }
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewModel.updateNotesListWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, width in
                        viewModel.updateNotesListWidth(width)
                    }
            }
        }
    }

    private func noteRow(for note: NoteDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.folder.isSensitive {
                    Image(systemName: note.folder.systemImage)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(displayTitle(for: note))
                    .font(.subheadline.weight(.semibold))
            }
            Label(note.folder.rawValue, systemImage: note.folder.systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder
    private func noteContextMenu(for note: NoteDocument) -> some View {
        Menu("Move to") {
            ForEach(NoteFolder.allCases.filter { $0 != note.folder }, id: \.self) { folder in
                Button {
                    Task { await viewModel.moveNote(note, to: folder) }
                } label: {
                    Label(folder.rawValue, systemImage: folder.systemImage)
                }
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            Task { await viewModel.deleteNote(note) }
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let note = selectedNote {
                editorHeader(for: note)

                if note.folder == .passwords {
                    PasswordNoteEditor(fields: $passwordFields)
                } else {
                    TextEditor(text: $editorText)
                        .font(.body.monospaced())
                        .padding(8)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(spacing: 12) {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteNote(note) }
                    }

                    Button("Save") {
                        Task { await saveCurrentNote(note) }
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
            } else {
                ContentUnavailableView(
                    "Select a note",
                    systemImage: "note.text",
                    description: Text("Create a note or pick one from the list.")
                )
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func editorHeader(for note: NoteDocument) -> some View {
        if note.folder == .passwords {
            TextField("Title", text: $passwordFields.name)
                .font(.title3.bold())
                .textFieldStyle(.plain)
        } else {
            TextField("Title", text: bindingTitle(for: note))
                .font(.title3.bold())
                .textFieldStyle(.plain)
        }

        Picker("Type", selection: bindingFolder(for: note)) {
            ForEach(NoteFolder.allCases, id: \.self) { folder in
                Label(folder.rawValue, systemImage: folder.systemImage)
                    .tag(folder)
            }
        }
        .pickerStyle(.segmented)

        if note.folder.isSensitive {
            Text("Stored in \(note.folder.rawValue). Syncs via iCloud — avoid sharing this device while unlocked.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedNote: NoteDocument? {
        guard let id = viewModel.selectedNoteID else { return nil }
        return viewModel.notes.first(where: { $0.id == id })
    }

    private var filteredNotes: [NoteDocument] {
        guard let listFilter else { return viewModel.notes }
        return viewModel.notes.filter { $0.folder == listFilter }
    }

    private func displayTitle(for note: NoteDocument) -> String {
        NotesMarkdown.title(from: note.markdown, fallback: note.title)
    }

    private func syncTitleFromMarkdown(_ markdown: String) {
        guard let note = selectedNote, note.folder != .passwords else { return }
        let newTitle = NotesMarkdown.title(from: markdown, fallback: note.title)
        guard let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) else { return }
        guard viewModel.notes[index].title != newTitle else { return }
        viewModel.notes[index].title = newTitle
    }

    private func syncTitleFromPasswordName(_ name: String) {
        guard let note = selectedNote, note.folder == .passwords else { return }
        let newTitle = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? note.title : name
        guard let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) else { return }
        guard viewModel.notes[index].title != newTitle else { return }
        viewModel.notes[index].title = newTitle
    }

    private func loadSelectedNote() {
        guard let note = selectedNote else {
            editorText = ""
            passwordFields = .empty()
            return
        }

        if note.folder == .passwords {
            passwordFields = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
            editorText = ""
            if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                viewModel.notes[index].title = passwordFields.name
            }
        } else {
            editorText = note.markdown
            passwordFields = .empty()
            if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                viewModel.notes[index].title = NotesMarkdown.title(from: editorText, fallback: note.title)
            }
        }
    }

    private func saveCurrentNote(_ note: NoteDocument) async {
        var updated = note
        updated.folder = bindingFolder(for: note).wrappedValue

        if updated.folder == .passwords {
            updated.markdown = passwordFields.markdown()
            updated.title = NotesMarkdown.title(from: updated.markdown, fallback: note.title)
        } else {
            let normalizedTitle = NotesMarkdown.title(from: editorText, fallback: note.title)
            updated.markdown = NotesMarkdown.settingTitle(normalizedTitle, in: editorText)
            updated.title = normalizedTitle
            editorText = updated.markdown
        }

        await viewModel.saveNote(updated)
    }

    private func bindingTitle(for note: NoteDocument) -> Binding<String> {
        Binding(
            get: {
                NotesMarkdown.title(from: editorText, fallback: note.title)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedTitle = trimmed.isEmpty ? note.title : trimmed
                editorText = NotesMarkdown.settingTitle(resolvedTitle, in: editorText)
                if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                    viewModel.notes[index].title = resolvedTitle
                }
            }
        )
    }

    private func bindingFolder(for note: NoteDocument) -> Binding<NoteFolder> {
        Binding(
            get: {
                viewModel.notes.first(where: { $0.id == note.id })?.folder ?? note.folder
            },
            set: { newValue in
                guard let current = viewModel.notes.first(where: { $0.id == note.id }) else { return }
                guard current.folder != newValue else { return }
                Task { await viewModel.moveNote(current, to: newValue) }
            }
        )
    }
}

private struct PasswordNoteEditor: View {
    @Binding var fields: PasswordNoteFields
    @State private var isPasswordVisible = false

    var body: some View {
        Form {
            TextField("URL", text: $fields.url)
            TextField("Username", text: $fields.username)
            TextField("Email", text: $fields.email)

            LabeledContent("Password") {
                HStack(spacing: 8) {
                    Group {
                        if isPasswordVisible {
                            TextField("Password", text: $fields.password)
                        } else {
                            SecureField("Password", text: $fields.password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button(isPasswordVisible ? "Hide" : "Show") {
                        isPasswordVisible.toggle()
                    }

                    Button("Copy") {
                        copyPassword()
                    }
                    .disabled(fields.password.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func copyPassword() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fields.password, forType: .string)
    }
}
