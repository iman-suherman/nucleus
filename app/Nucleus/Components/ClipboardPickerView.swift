import AppKit
import ClipboardKit
import NucleusKit
import SwiftUI

@MainActor
final class ClipboardPickerKeyboardBridge {
    var isEnabled = true
    var isSearchFocused = false
    var focusSearch: (() -> Void)?
    var appendToQuery: ((String) -> Void)?
    var deleteFromQuery: (() -> Void)?
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    var submit: (() -> Void)?
    var dismiss: (() -> Void)?
}

struct ClipboardPickerView: View {
    let entries: [ClipboardEntry]
    let onSelect: (ClipboardEntry) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var highlightedID: UUID?
    @State private var confirmedSelectionID: UUID?
    @State private var isConfirmingSelection = false
    @State private var keyboardBridge = ClipboardPickerKeyboardBridge()
    @FocusState private var searchFocused: Bool

    private let selectionConfirmationDelay: Duration = .milliseconds(1000)

    private var filteredEntries: [ClipboardEntry] {
        ClipboardSearch.rank(entries, query: query)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Paste from Clipboard History")
                    .font(.headline)
                Spacer()
                Text("⇧⌘V")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("Search clips…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .disabled(isConfirmingSelection)

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No matching clips",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy something first, then press Shift-Command-V.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $highlightedID) {
                        ForEach(filteredEntries) { entry in
                            ClipboardPickerRow(
                                entry: entry,
                                isHighlighted: highlightedID == entry.id,
                                isConfirmed: confirmedSelectionID == entry.id
                            )
                            .id(entry.id)
                            .tag(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !isConfirmingSelection else { return }
                                confirmSelection(entry)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .focusable(false)
                    .onChange(of: highlightedID) { _, id in
                        scrollToHighlight(id, proxy: proxy)
                    }
                    .onChange(of: filteredEntries.map(\.id)) { _, _ in
                        scrollToHighlight(highlightedID, proxy: proxy)
                    }
                    .onAppear {
                        scrollToHighlight(highlightedID, proxy: proxy)
                    }
                }
            }

            Text("Type to search · ↑↓ to move · Return to select · ⌘V to paste · Esc to close")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 520, height: 360)
        .background {
            ClipboardPickerKeyMonitor(bridge: keyboardBridge)
        }
        .onAppear {
            syncKeyboardBridge()
            highlightedID = filteredEntries.first?.id
            searchFocused = true
        }
        .onChange(of: query) { _, _ in
            guard !isConfirmingSelection else { return }
            highlightedID = filteredEntries.first?.id
        }
        .onChange(of: isConfirmingSelection) { _, _ in
            syncKeyboardBridge()
        }
        .onChange(of: searchFocused) { _, _ in
            syncKeyboardBridge()
        }
        .onExitCommand {
            guard !isConfirmingSelection else { return }
            onDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard !isConfirmingSelection else { return }
            searchFocused = true
        }
    }

    private func syncKeyboardBridge() {
        keyboardBridge.isEnabled = !isConfirmingSelection
        keyboardBridge.isSearchFocused = searchFocused
        keyboardBridge.focusSearch = {
            searchFocused = true
        }
        keyboardBridge.appendToQuery = { text in
            query += text
        }
        keyboardBridge.deleteFromQuery = {
            guard !query.isEmpty else { return }
            query.removeLast()
        }
        keyboardBridge.moveUp = {
            moveHighlight(by: -1)
        }
        keyboardBridge.moveDown = {
            moveHighlight(by: 1)
        }
        keyboardBridge.submit = {
            submitHighlightedSelection()
        }
        keyboardBridge.dismiss = {
            onDismiss()
        }
    }

    private func scrollToHighlight(_ id: UUID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func moveHighlight(by offset: Int) {
        guard !isConfirmingSelection, !filteredEntries.isEmpty else { return }
        guard let currentID = highlightedID,
              let index = filteredEntries.firstIndex(where: { $0.id == currentID }) else {
            highlightedID = filteredEntries.first?.id
            return
        }
        let nextIndex = min(max(index + offset, 0), filteredEntries.count - 1)
        highlightedID = filteredEntries[nextIndex].id
    }

    private func submitHighlightedSelection() {
        guard !isConfirmingSelection,
              let highlightedID,
              let entry = filteredEntries.first(where: { $0.id == highlightedID }) else {
            return
        }
        confirmSelection(entry)
    }

    private func confirmSelection(_ entry: ClipboardEntry) {
        guard !isConfirmingSelection else { return }
        isConfirmingSelection = true
        highlightedID = entry.id
        confirmedSelectionID = entry.id

        Task {
            try? await Task.sleep(for: selectionConfirmationDelay)
            onSelect(entry)
        }
    }
}

private struct ClipboardPickerKeyMonitor: NSViewRepresentable {
    let bridge: ClipboardPickerKeyboardBridge

    func makeNSView(context: Context) -> ClipboardPickerKeyMonitorView {
        let view = ClipboardPickerKeyMonitorView()
        view.bridge = bridge
        return view
    }

    func updateNSView(_ nsView: ClipboardPickerKeyMonitorView, context: Context) {
        nsView.bridge = bridge
    }
}

private final class ClipboardPickerKeyMonitorView: NSView {
    var bridge: ClipboardPickerKeyboardBridge?
    private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installKeyMonitor()
        } else {
            removeKeyMonitor()
        }
    }

    deinit {
        removeKeyMonitor()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let bridge, bridge.isEnabled else { return event }

        switch event.keyCode {
        case 53:
            bridge.dismiss?()
            return nil
        case 126:
            bridge.moveUp?()
            return nil
        case 125:
            bridge.moveDown?()
            return nil
        case 36, 76:
            bridge.submit?()
            return nil
        default:
            break
        }

        guard shouldCaptureTyping(event) else { return event }

        if bridge.isSearchFocused || Self.isSearchFieldFirstResponder(in: window) {
            return event
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            bridge.focusSearch?()
            bridge.deleteFromQuery?()
            return nil
        }

        if let characters = event.characters, !characters.isEmpty {
            bridge.focusSearch?()
            bridge.appendToQuery?(characters)
            return nil
        }

        return event
    }

    private func shouldCaptureTyping(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags.contains(.command) || flags.contains(.control) {
            return false
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            return true
        }

        guard let characters = event.characters, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            if CharacterSet.alphanumerics.contains(scalar) { return true }
            if CharacterSet.punctuationCharacters.contains(scalar) { return true }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
            if CharacterSet.symbols.contains(scalar) { return true }
            return false
        }
    }

    private static func isSearchFieldFirstResponder(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder is NSTextField || responder is NSTextView {
            return true
        }
        if let view = responder as? NSView {
            let name = String(describing: type(of: view))
            return name.contains("TextField") || name.contains("TextEditor")
        }
        return false
    }
}

private struct ClipboardPickerRow: View {
    let entry: ClipboardEntry
    var isHighlighted: Bool = false
    var isConfirmed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.sourceApplication)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isConfirmed {
                    Text("Selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }
                Text(NucleusFormatters.relativeDate.localizedString(for: entry.capturedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.content)
                .font(.body.monospaced())
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowBackground)
        )
    }

    private var rowBackground: Color {
        if isConfirmed {
            return Color.accentColor.opacity(0.28)
        }
        if isHighlighted {
            return Color.accentColor.opacity(0.12)
        }
        return Color.clear
    }
}
