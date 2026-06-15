import NucleusKit
import SwiftUI

struct NotesWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @State private var editorText = ""
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
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("All categories") { listFilter = nil }
                    Divider()
                    ForEach(NoteFolder.allCases, id: \.self) { folder in
                        Button {
                            listFilter = folder
                        } label: {
                            Label(folder.rawValue, systemImage: folder.systemImage)
                        }
                    }
                } label: {
                    Label(listFilter?.rawValue ?? "All", systemImage: listFilter?.systemImage ?? "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                }
                Menu("New") {
                    ForEach(NoteFolder.allCases, id: \.self) { folder in
                        Button {
                            Task { await viewModel.createNote(in: folder) }
                        } label: {
                            Label(folder.rawValue, systemImage: folder.systemImage)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            List(selection: $viewModel.selectedNoteID) {
                ForEach(filteredNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if note.folder.isSensitive {
                                Image(systemName: note.folder.systemImage)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(note.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        Label(note.folder.rawValue, systemImage: note.folder.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                    .tag(Optional(note.id))
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

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let note = selectedNote {
                TextField("Title", text: bindingTitle(for: note))
                    .font(.title3.bold())
                    .textFieldStyle(.plain)

                Picker("Category", selection: bindingFolder(for: note)) {
                    ForEach(NoteFolder.allCases, id: \.self) { folder in
                        Label(folder.rawValue, systemImage: folder.systemImage)
                            .tag(folder)
                    }
                }
                .pickerStyle(.menu)

                if note.folder.isSensitive {
                    Text("Stored in \(note.folder.rawValue). Syncs via iCloud — avoid sharing this device while unlocked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $editorText)
                    .font(.body.monospaced())
                    .padding(8)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Spacer()
                    Button("Save") {
                        Task {
                            var updated = note
                            updated.markdown = editorText
                            updated.title = titleFromMarkdown(editorText, fallback: note.title)
                            updated.folder = bindingFolder(for: note).wrappedValue
                            await viewModel.saveNote(updated)
                        }
                    }
                    .buttonStyle(.borderedProminent)
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

    private var selectedNote: NoteDocument? {
        guard let id = viewModel.selectedNoteID else { return nil }
        return viewModel.notes.first(where: { $0.id == id })
    }

    private var filteredNotes: [NoteDocument] {
        guard let listFilter else { return viewModel.notes }
        return viewModel.notes.filter { $0.folder == listFilter }
    }

    private func loadSelectedNote() {
        editorText = selectedNote?.markdown ?? ""
    }

    private func bindingTitle(for note: NoteDocument) -> Binding<String> {
        Binding(
            get: { note.title },
            set: { newValue in
                if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                    viewModel.notes[index].title = newValue
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
                if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                    viewModel.notes[index].folder = newValue
                }
            }
        )
    }

    private func titleFromMarkdown(_ markdown: String, fallback: String) -> String {
        markdown
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("#") })
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) }
            ?? fallback
    }
}
