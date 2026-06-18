import AppKit
import NucleusKit
import SwiftUI

struct ClipboardPickerView: View {
    let entries: [ClipboardEntry]
    let onSelect: (ClipboardEntry) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var highlightedID: UUID?
    @FocusState private var searchFocused: Bool

    private var filteredEntries: [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        let lower = trimmed.lowercased()
        return entries.filter {
            $0.content.lowercased().contains(lower)
                || $0.sourceApplication.lowercased().contains(lower)
                || $0.tags.contains(where: { $0.lowercased().contains(lower) })
        }
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

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No matching clips",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy something first, then press Shift-Command-V.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $highlightedID) {
                    ForEach(filteredEntries) { entry in
                        ClipboardPickerRow(entry: entry)
                            .tag(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(entry)
                            }
                    }
                }
                .listStyle(.inset)
            }

            Text("Click a clip to paste · Return on selection · Esc to close")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 520, height: 360)
        .onAppear {
            highlightedID = filteredEntries.first?.id
            searchFocused = true
        }
        .onChange(of: query) { _, _ in
            highlightedID = filteredEntries.first?.id
        }
        .onExitCommand(perform: onDismiss)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            searchFocused = true
        }
        .background(
            ClipboardPickerKeyHandler(
                onReturn: {
                    guard let highlightedID,
                          let entry = filteredEntries.first(where: { $0.id == highlightedID }) else {
                        return
                    }
                    onSelect(entry)
                },
                onMoveUp: { moveHighlight(by: -1) },
                onMoveDown: { moveHighlight(by: 1) },
                onEscape: onDismiss
            )
        )
    }

    private func moveHighlight(by offset: Int) {
        guard !filteredEntries.isEmpty else { return }
        guard let currentID = highlightedID,
              let index = filteredEntries.firstIndex(where: { $0.id == currentID }) else {
            highlightedID = filteredEntries.first?.id
            return
        }
        let nextIndex = min(max(index + offset, 0), filteredEntries.count - 1)
        highlightedID = filteredEntries[nextIndex].id
    }
}

private struct ClipboardPickerRow: View {
    let entry: ClipboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.sourceApplication)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(NucleusFormatters.relativeDate.localizedString(for: entry.capturedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.content)
                .font(.body.monospaced())
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

private struct ClipboardPickerKeyHandler: NSViewRepresentable {
    let onReturn: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onReturn = onReturn
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onEscape = onEscape
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyCatcherView else { return }
        view.onReturn = onReturn
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onEscape = onEscape
    }
}

private final class KeyCatcherView: NSView {
    var onReturn: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            onReturn?()
        case 126:
            onMoveUp?()
        case 125:
            onMoveDown?()
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}
