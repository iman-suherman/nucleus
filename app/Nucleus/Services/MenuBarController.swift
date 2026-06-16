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

    private var modelContainer: ModelContainer?
    private var onDataChanged: (() -> Void)?
    private var isMonitoring = false

    func configure(modelContainer: ModelContainer, onDataChanged: @escaping () -> Void) {
        self.modelContainer = modelContainer
        self.onDataChanged = onDataChanged
    }

    func applySettings(_ settings: AppSettings) {
        if settings.menuBarEnabled {
            startMonitoring()
            reload()
        } else {
            stopMonitoring()
            pendingSuggestion = nil
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

    func dismissSuggestion() {
        if let pendingSuggestion {
            NucleusMenuBarBridge.rememberDismissedPassword(pendingSuggestion.password)
        }
        pendingSuggestion = nil
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

        let payload = ClipboardPasswordSuggestionPayload(
            entryID: entry.id,
            password: analysis.extractedPassword,
            sourceApplication: capture.sourceApplication,
            capturedAt: capture.capturedAt,
            reason: analysis.reason
        )
        pendingSuggestion = payload
        let fields = PasswordNoteFields.fromDetectedPassword(
            analysis.extractedPassword,
            source: capture.sourceApplication
        )
        passwordDraftName = fields.name
        passwordDraftURL = fields.url
        passwordDraftUsername = fields.username
        passwordDraftEmail = fields.email

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
