import AppKit
import DatabaseKit
import NotesKit
import NucleusKit
import SwiftUI
import SyncKit
import WebKit

private enum NoteSaveStatus: Equatable {
    case idle
    case saving
    case saved
}

private enum NoteEditorMode: String, CaseIterable, Identifiable {
    case edit
    case preview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .edit: return "Edit"
        case .preview: return "Preview"
        }
    }
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
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .saved:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NotesWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var syncService = CloudKitSyncService.shared
    @State private var editorText = ""
    @State private var passwordFields = PasswordNoteFields.empty()
    @State private var saveStatus: NoteSaveStatus = .idle
    @State private var savedSnapshot: NoteEditorSnapshot?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var savedIndicatorTask: Task<Void, Never>?
    @State private var editorMode: NoteEditorMode = .edit

    var body: some View {
        ZStack {
            HSplitView {
                notesList
                    .frame(minWidth: 240, idealWidth: appSettings.notesListWidth, maxWidth: 340)

                noteEditor
                    .frame(minWidth: 420)
            }

            if let prompt = viewModel.dashboardIncomingMailPrompt {
                DashboardIncomingMailOverlay(
                    prompt: prompt,
                    onOpenInbox: viewModel.openDashboardIncomingMail,
                    onDismiss: viewModel.dismissDashboardIncomingMail
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.dashboardIncomingMailPrompt?.id)
        .onAppear {
            loadSelectedNote()
            viewModel.refreshDashboardIncomingMailAlertIfNeeded()
        }
        .onChange(of: viewModel.selectedNoteID) { oldID, newID in
            if let oldID, oldID != newID,
               let note = viewModel.notes.first(where: { $0.id == oldID }) {
                autoSaveTask?.cancel()
                if isDirty(for: note) {
                    let updated = buildUpdatedNote(from: note)
                    Task {
                        saveStatus = .saving
                        await viewModel.saveNote(updated)
                    }
                }
            }
            loadSelectedNote()
        }
        .onChange(of: editorText) { _, _ in
            syncTitleFromMarkdown(editorText)
            scheduleAutoSave()
        }
        .onChange(of: passwordFields) { _, _ in
            syncTitleFromPasswordName(passwordFields.name)
            scheduleAutoSave()
        }
    }

    private var notesCount: Int {
        viewModel.regularNotesCount
    }

    private var passwordsCount: Int {
        viewModel.passwordNotesCount
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Notes and Passwords")
                    .font(.headline)
                NoteFolderCountBadges(
                    notesCount: viewModel.regularNotesCount,
                    passwordsCount: viewModel.passwordNotesCount
                )
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

            folderFilterBar

            NotesICloudSyncStatusCard(syncService: syncService)
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

    private var folderFilterBar: some View {
        HStack(spacing: 4) {
            folderFilterOption(title: "All", folder: nil)
            folderFilterOption(
                title: NoteFolder.notes.rawValue,
                folder: .notes,
                count: notesCount,
                accent: .blue
            )
            folderFilterOption(
                title: NoteFolder.passwords.rawValue,
                folder: .passwords,
                count: passwordsCount,
                accent: .orange
            )
        }
        .padding(4)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private func folderFilterOption(
        title: String,
        folder: NoteFolder?,
        count: Int? = nil,
        accent: Color? = nil
    ) -> some View {
        let isSelected = viewModel.notesFolderFilter == folder

        return Button {
            viewModel.notesFolderFilter = folder
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                if let count, let accent {
                    NoteFolderCountBadge(count: count, accent: accent)
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if editorMode == .edit {
                    TextEditor(text: $editorText)
                        .font(.body.monospaced())
                        .padding(8)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                        .frame(maxHeight: .infinity)
                } else {
                    NoteMarkdownPreview(markdown: editorText)
                        .frame(maxHeight: .infinity)
                }

                HStack(spacing: 12) {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteNote(note) }
                    }

                    NoteSaveStatusIndicator(status: saveStatus)

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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 6) {
                Label(note.folder.rawValue, systemImage: note.folder.systemImage)
                    .labelStyle(.titleAndIcon)
                NoteFolderCountBadge(
                    count: note.folder == .notes ? notesCount : passwordsCount,
                    accent: note.folder == .notes ? .blue : .orange
                )
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            if note.folder != .passwords {
                TextField("Title", text: bindingTitle(for: note))
                    .font(.title3.bold())
                    .textFieldStyle(.plain)
            } else {
                Text(passwordFields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Entry" : passwordFields.name)
                    .font(.title3.bold())
                    .foregroundStyle(passwordFields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .tertiary : .primary)
            }
        }

        if note.folder != .passwords {
            Picker("View", selection: $editorMode) {
                ForEach(NoteEditorMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }

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
        guard let notesFolderFilter = viewModel.notesFolderFilter else { return viewModel.notes }
        return viewModel.notes.filter { $0.folder == notesFolderFilter }
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

    private func isDirty(for note: NoteDocument) -> Bool {
        guard let savedSnapshot else { return true }
        return editorSnapshot(for: note) != savedSnapshot
    }

    private func editorSnapshot(for note: NoteDocument) -> NoteEditorSnapshot {
        let folder = currentFolder(for: note)

        if folder == .passwords {
            let markdown = passwordFields.markdown()
            let title = NotesMarkdown.title(from: markdown, fallback: note.title)
            return NoteEditorSnapshot(markdown: markdown, title: title, folder: folder)
        }

        let normalizedTitle = NotesMarkdown.title(from: editorText, fallback: note.title)
        let markdown = NotesMarkdown.settingTitle(normalizedTitle, in: editorText)
        return NoteEditorSnapshot(markdown: markdown, title: normalizedTitle, folder: folder)
    }

    private func buildUpdatedNote(from note: NoteDocument) -> NoteDocument {
        var updated = note
        let snapshot = editorSnapshot(for: note)
        updated.folder = snapshot.folder
        updated.markdown = snapshot.markdown
        updated.title = snapshot.title
        return updated
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard let note = selectedNote, isDirty(for: note) else { return }

        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled,
                  let note = selectedNote,
                  isDirty(for: note) else { return }
            await saveCurrentNote(note)
        }
    }

    private func loadSelectedNote() {
        autoSaveTask?.cancel()
        saveStatus = .idle
        savedIndicatorTask?.cancel()
        editorMode = .edit

        guard let note = selectedNote else {
            editorText = ""
            passwordFields = .empty()
            savedSnapshot = nil
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

        savedSnapshot = editorSnapshot(for: note)
    }

    private func saveCurrentNote(_ note: NoteDocument) async {
        guard isDirty(for: note) else { return }

        saveStatus = .saving
        let updated = buildUpdatedNote(from: note)

        if updated.folder != .passwords {
            editorText = updated.markdown
        }

        await viewModel.saveNote(updated)
        savedSnapshot = editorSnapshot(for: updated)
        markSaved()
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

    private func currentFolder(for note: NoteDocument) -> NoteFolder {
        viewModel.notes.first(where: { $0.id == note.id })?.folder ?? note.folder
    }
}

private struct NoteMarkdownPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let markdown: String

    private var bodyMarkdown: String {
        NotesMarkdown.body(from: markdown)
    }

    var body: some View {
        Group {
            if bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Nothing to preview yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            } else {
                NoteMarkdownWebPreview(markdown: markdown, colorScheme: colorScheme)
            }
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NoteMarkdownWebPreview: NSViewRepresentable {
    let markdown: String
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.drawsBackground = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let scheme = colorScheme == .dark ? "dark" : "light"
        let html = NotesMarkdownHTML.previewDocument(from: markdown, colorScheme: scheme)
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var loadedHTML: String?
    }
}

private struct NotesICloudSyncStatusCard: View {
    @ObservedObject var syncService: CloudKitSyncService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusIconColor)
                Text(syncStatusTitle)
                    .font(.subheadline.weight(.semibold))
                if syncService.isNotesSyncInProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            LabeledContent("iCloud account") {
                Text(syncService.iCloudAccountDisplayName)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)

            LabeledContent("Sync") {
                Text(notesStorageLabel)
                    .foregroundStyle(notesStorageColor)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)

            if let lastSync = syncService.lastRemoteChangeAt {
                LabeledContent("Last sync") {
                    Text(lastSync, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else if NucleusDatabase.usesCloudKitSync, syncService.status.isAvailable {
                LabeledContent("Last sync") {
                    Text("Waiting for first update")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if let error = NucleusDatabase.lastCloudKitSetupError, !NucleusDatabase.usesCloudKitSync {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var syncStatusTitle: String {
        if syncService.status == .checking {
            return "Checking iCloud…"
        }
        if syncService.isNotesSyncInProgress {
            return "Syncing notes…"
        }
        if NucleusDatabase.usesCloudKitSync, syncService.status.isAvailable {
            return "Notes synced"
        }
        return syncService.status.label
    }

    private var statusIcon: String {
        if syncService.isNotesSyncInProgress || syncService.status == .checking {
            return "arrow.triangle.2.circlepath.icloud"
        }
        if NucleusDatabase.usesCloudKitSync, syncService.status.isAvailable {
            return "checkmark.icloud.fill"
        }
        return "icloud.slash"
    }

    private var statusIconColor: Color {
        if NucleusDatabase.usesCloudKitSync, syncService.status.isAvailable {
            return .green
        }
        if syncService.status == .checking || syncService.isNotesSyncInProgress {
            return .secondary
        }
        return .orange
    }

    private var notesStorageLabel: String {
        if NucleusDatabase.usesCloudKitSync {
            return "iCloud CloudKit"
        }
        return "This Mac only"
    }

    private var notesStorageColor: Color {
        NucleusDatabase.usesCloudKitSync ? Color.secondary : Color.orange
    }
}

private struct PasswordNoteEditor: View {
    @Binding var fields: PasswordNoteFields
    @State private var isPasswordVisible = false

    var body: some View {
        Form {
            TextField("Title", text: $fields.name)
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
