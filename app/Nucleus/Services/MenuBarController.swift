import AppKit
import ClipboardKit
import DatabaseKit
import Foundation
import NotesKit
import NucleusKit
import SwiftData

@MainActor
final class MenuBarController: ObservableObject {
    @Published private(set) var clipboardEntries: [ClipboardEntry] = []
    @Published private(set) var passwordNotes: [NoteDocument] = []
    @Published var pendingSuggestion: ClipboardPasswordSuggestionPayload?
    @Published var passwordDraftName = ""
    @Published var passwordDraftURL = ""
    @Published var passwordDraftUsername = ""
    @Published var passwordDraftEmail = ""

    @Published private(set) var editingPasswordID: UUID?
    @Published var editingDraftName = ""
    @Published var editingDraftURL = ""
    @Published var editingDraftUsername = ""
    @Published var editingDraftEmail = ""
    @Published var editingDraftPassword = ""
    @Published var passwordPendingDeletionID: UUID?

    var isEditingPassword: Bool { editingPasswordID != nil }

    private var modelContainer: ModelContainer?
    private var onDataChanged: (() -> Void)?
    private var isMonitoring = false

    func configure(modelContainer: ModelContainer, onDataChanged: @escaping () -> Void) {
        self.modelContainer = modelContainer
        self.onDataChanged = onDataChanged
    }

    func applySettings(_ settings: AppSettings, syncStatusItem: Bool = true) {
        if settings.menuBarEnabled {
            startMonitoring()
            reload()
        } else {
            stopMonitoring()
            pendingSuggestion = nil
        }
        if syncStatusItem {
            MenuBarCoordinator.sync(settings: settings, controller: self)
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        ClipboardMonitorService.shared.onCapture = { [weak self] capture in
            Task { @MainActor in
                self?.handleCapture(capture)
            }
        }
        ClipboardMonitorService.shared.isCaptureEnabled = {
            AppSettings.shared.menuBarEnabled
        }
        ClipboardMonitorService.shared.start()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        ClipboardMonitorService.shared.stop()
    }

    func reload() {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        clipboardEntries = (try? ClipboardRepository.fetchRecent(context: context, limit: 10)) ?? []
        let notes = (try? NoteRepository.fetchAll(context: context)) ?? []
        passwordNotes = notes.filter { $0.folder == .passwords }
    }

    func copyEntry(_ entry: ClipboardEntry) {
        ClipboardMonitorService.copyToPasteboard(entry.content)
    }

    func copyPassword(_ note: NoteDocument) {
        let fields = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
        guard !fields.password.isEmpty else { return }
        ClipboardMonitorService.copyToPasteboard(fields.password)
    }

    func copyUsername(_ note: NoteDocument) {
        let fields = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
        guard !fields.username.isEmpty else { return }
        ClipboardMonitorService.copyToPasteboard(fields.username)
    }

    func copyEmail(_ note: NoteDocument) {
        let fields = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
        guard !fields.email.isEmpty else { return }
        ClipboardMonitorService.copyToPasteboard(fields.email)
    }

    func openPasswordURL(_ note: NoteDocument) {
        let fields = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
        let trimmed = fields.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var urlString = trimmed
        if !urlString.contains("://") {
            urlString = "https://\(urlString)"
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func beginEditingPassword(_ note: NoteDocument) {
        let fields = PasswordNoteFields.parse(from: note.markdown, fallbackTitle: note.title)
        editingPasswordID = note.id
        editingDraftName = fields.name
        editingDraftURL = fields.url
        editingDraftUsername = fields.username
        editingDraftEmail = fields.email
        editingDraftPassword = fields.password
    }

    func cancelEditingPassword() {
        editingPasswordID = nil
        editingDraftName = ""
        editingDraftURL = ""
        editingDraftUsername = ""
        editingDraftEmail = ""
        editingDraftPassword = ""
    }

    func saveEditedPassword() {
        guard let editingPasswordID, let modelContainer else { return }
        guard let note = passwordNotes.first(where: { $0.id == editingPasswordID }) else {
            cancelEditingPassword()
            return
        }

        let fields = PasswordNoteFields(
            name: editingDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? note.title
                : editingDraftName.trimmingCharacters(in: .whitespacesAndNewlines),
            url: editingDraftURL,
            username: editingDraftUsername,
            email: editingDraftEmail,
            password: editingDraftPassword
        )

        var updated = note
        updated.title = fields.name
        updated.markdown = fields.markdown()
        updated.updatedAt = Date()

        let context = ModelContext(modelContainer)
        try? NoteRepository.upsert(updated, context: context)
        cancelEditingPassword()
        notifyDataChanged()
    }

    func requestDeletePassword(_ note: NoteDocument) {
        passwordPendingDeletionID = note.id
    }

    func cancelDeletePassword() {
        passwordPendingDeletionID = nil
    }

    func confirmDeletePassword() {
        guard let passwordPendingDeletionID, let modelContainer else { return }
        let context = ModelContext(modelContainer)
        try? NoteRepository.delete(id: passwordPendingDeletionID, context: context)
        if editingPasswordID == passwordPendingDeletionID {
            cancelEditingPassword()
        }
        self.passwordPendingDeletionID = nil
        notifyDataChanged()
    }

    func passwordNote(for id: UUID) -> NoteDocument? {
        passwordNotes.first { $0.id == id }
    }

    func dismissSuggestion() {
        if let pendingSuggestion {
            NucleusMenuBarBridge.rememberDismissedPassword(pendingSuggestion.password)
            NucleusNotificationService.shared.clearPasswordNotification(entryID: pendingSuggestion.entryID)
        }
        pendingSuggestion = nil
    }

    @discardableResult
    func presentPasswordSuggestion(entryID: UUID) -> Bool {
        reload()
        if pendingSuggestion?.entryID == entryID {
            return true
        }
        guard let entry = clipboardEntries.first(where: { $0.id == entryID }),
              let analysis = ClipboardPasswordAnalyzer.analyze(entry.content) else {
            return false
        }
        applyPasswordSuggestion(
            entry: entry,
            password: analysis.extractedPassword,
            reason: analysis.reason
        )
        return true
    }

    func dismissPasswordSuggestion(entryID: UUID) {
        NucleusNotificationService.shared.clearPasswordNotification(entryID: entryID)
        if pendingSuggestion?.entryID == entryID {
            dismissSuggestion()
            return
        }
        guard let entry = clipboardEntries.first(where: { $0.id == entryID }),
              let analysis = ClipboardPasswordAnalyzer.analyze(entry.content) else {
            return
        }
        NucleusMenuBarBridge.rememberDismissedPassword(analysis.extractedPassword)
    }

    private func applyPasswordSuggestion(
        entry: ClipboardEntry,
        password: String,
        reason: String
    ) {
        pendingSuggestion = ClipboardPasswordSuggestionPayload(
            entryID: entry.id,
            password: password,
            sourceApplication: entry.sourceApplication,
            capturedAt: entry.capturedAt,
            reason: reason
        )
        let fields = PasswordNoteFields.fromDetectedPassword(password, source: entry.sourceApplication)
        passwordDraftName = fields.name
        passwordDraftURL = fields.url
        passwordDraftUsername = fields.username
        passwordDraftEmail = fields.email
    }

    func saveSuggestion() {
        guard let suggestion = pendingSuggestion, let modelContainer else { return }
        let fields = PasswordNoteFields(
            name: passwordDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "New Entry"
                : passwordDraftName.trimmingCharacters(in: .whitespacesAndNewlines),
            url: passwordDraftURL,
            username: passwordDraftUsername,
            email: passwordDraftEmail,
            password: suggestion.password
        )
        let note = NoteDocument(
            title: fields.name,
            markdown: fields.markdown(),
            folder: .passwords
        )
        let context = ModelContext(modelContainer)
        try? NoteRepository.upsert(note, context: context)
        NucleusMenuBarBridge.rememberDismissedPassword(suggestion.password)
        NucleusNotificationService.shared.clearPasswordNotification(entryID: suggestion.entryID)
        pendingSuggestion = nil
        notifyDataChanged()
    }

    private func handleCapture(_ capture: ClipboardCapture) {
        guard AppSettings.shared.menuBarEnabled else { return }
        guard !NucleusMenuBarBridge.isNucleusFamilyApp(capture.sourceApplication) else { return }
        guard let modelContainer else { return }

        let entry = capture.asEntry()
        let context = ModelContext(modelContainer)
        try? ClipboardRepository.insert(entry, context: context)
        reload()
        notifyDataChanged()
        evaluatePassword(entry: entry, capture: capture)
    }

    private func evaluatePassword(entry: ClipboardEntry, capture: ClipboardCapture) {
        guard AppSettings.shared.clipboardPasswordDetectionEnabled else { return }
        guard let analysis = ClipboardPasswordAnalyzer.analyze(capture.content) else { return }
        guard !NucleusMenuBarBridge.isDismissedPassword(analysis.extractedPassword) else { return }

        applyPasswordSuggestion(
            entry: entry,
            password: analysis.extractedPassword,
            reason: analysis.reason
        )

        NucleusNotificationService.shared.notifyClipboardPasswordSuggestion(
            ClipboardPasswordSuggestion(
                id: entry.id,
                password: analysis.extractedPassword,
                sourceApplication: capture.sourceApplication,
                capturedAt: capture.capturedAt,
                reason: analysis.reason
            )
        )
    }

    private func notifyDataChanged() {
        reload()
        onDataChanged?()
    }
}
