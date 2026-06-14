import NucleusKit
import SwiftUI

struct NotesWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var editorText = ""

    var body: some View {
        HSplitView {
            notesList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

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
                Menu("New") {
                    ForEach(NoteFolder.allCases, id: \.self) { folder in
                        Button(folder.rawValue) {
                            Task { await viewModel.createNote(in: folder) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            List(selection: $viewModel.selectedNoteID) {
                ForEach(viewModel.notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.subheadline.weight(.semibold))
                        Text(note.folder.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(note.id))
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

                Text("Folder: \(note.folder.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

    private func titleFromMarkdown(_ markdown: String, fallback: String) -> String {
        markdown
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("#") })
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) }
            ?? fallback
    }
}
