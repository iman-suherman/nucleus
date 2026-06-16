import AppKit
import ClipboardKit
import DatabaseKit
import Foundation
import NotesKit
import NucleusKit
import SwiftData

@MainActor
final class MenuBarDataController: ObservableObject {
    @Published private(set) var clipboardEntries: [ClipboardEntry] = []
    @Published private(set) var passwordNotes: [NoteDocument] = []
    @Published var pendingSuggestion: ClipboardPasswordSuggestionPayload?
    @Published var passwordDraftName = ""
    @Published var passwordDraftURL = ""
    @Published var passwordDraftUsername = ""
    @Published var passwordDraftEmail = ""

    let modelContainer: ModelContainer
    private var refreshObserver: NSObjectProtocol?
    private var suggestionObserver: NSObjectProtocol?

    init() {
        modelContainer = (try? NucleusDatabase.makeContainer(enableCloudKit: false)) ?? {
            fatalError("Failed to open Nucleus database for menu bar companion")
        }()

        ClipboardMonitorService.shared.onCapture = { [weak self] capture in
            Task { @MainActor in
                self?.handleCapture(capture)
            }
        }

        refreshObserver = DarwinNotificationCenter.observe(NucleusMenuBarBridge.darwinRefreshNotification) { [weak self] in
            Task { @MainActor in
                self?.reload()
            }
        }

        suggestionObserver = DarwinNotificationCenter.observe(NucleusMenuBarBridge.darwinPasswordSuggestionNotification) { [weak self] in
            Task { @MainActor in
                self?.loadPendingSuggestion()
            }
        }

        reload()
        loadPendingSuggestion()
        ClipboardMonitorService.shared.start()
    }

    deinit {
        if let refreshObserver { DarwinNotificationCenter.remove(refreshObserver) }
        if let suggestionObserver { DarwinNotificationCenter.remove(suggestionObserver) }
    }

    func reload() {
        let context = ModelContext(modelContainer)
        clipboardEntries = (try? ClipboardRepository.fetchRecent(context: context, limit: 10)) ?? []
        let notes = (try? NoteRepository.fetchAll(context: context)) ?? []
        passwordNotes = notes.filter { $0.folder == .passwords }
    }

    func loadPendingSuggestion() {
        pendingSuggestion = NucleusMenuBarBridge.pendingSuggestion()
        if let pendingSuggestion {
            let fields = PasswordNoteFields.fromDetectedPassword(
                pendingSuggestion.password,
                source: pendingSuggestion.sourceApplication
            )
            passwordDraftName = fields.name
            passwordDraftURL = fields.url
            passwordDraftUsername = fields.username
            passwordDraftEmail = fields.email
        }
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
        NucleusMenuBarBridge.clearPendingSuggestion()
        pendingSuggestion = nil
    }

    func saveSuggestion() {
        guard let suggestion = pendingSuggestion else { return }
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
        NucleusMenuBarBridge.clearPendingSuggestion()
        pendingSuggestion = nil
        NucleusMenuBarBridge.postDataRefresh()
        reload()
    }

    private func handleCapture(_ capture: ClipboardCapture) {
        guard !NucleusMenuBarBridge.isNucleusFamilyApp(capture.sourceApplication) else { return }

        let entry = capture.asEntry()
        let context = ModelContext(modelContainer)
        try? ClipboardRepository.insert(entry, context: context)
        reload()
        NucleusMenuBarBridge.postDataRefresh()

        evaluatePassword(entry: entry, capture: capture)
    }

    private func evaluatePassword(entry: ClipboardEntry, capture: ClipboardCapture) {
        guard UserDefaults.standard.object(forKey: "nucleus.settings.clipboardPasswordDetectionEnabled") as? Bool ?? true else {
            return
        }
        guard let analysis = ClipboardPasswordAnalyzer.analyze(capture.content) else { return }
        guard !NucleusMenuBarBridge.isDismissedPassword(analysis.extractedPassword) else { return }

        let payload = ClipboardPasswordSuggestionPayload(
            entryID: entry.id,
            password: analysis.extractedPassword,
            sourceApplication: capture.sourceApplication,
            capturedAt: capture.capturedAt,
            reason: analysis.reason
        )
        NucleusMenuBarBridge.setPendingSuggestion(payload)
        pendingSuggestion = payload
        passwordDraftName = PasswordNoteFields.fromDetectedPassword(
            analysis.extractedPassword,
            source: capture.sourceApplication
        ).name
    }
}

enum DarwinNotificationCenter {
    static func observe(_ name: String, handler: @escaping () -> Void) -> NSObjectProtocol {
        NucleusDarwinNotifications.observe(name, handler: handler)
    }

    static func remove(_ token: NSObjectProtocol) {
        NucleusDarwinNotifications.remove(token)
    }
}
