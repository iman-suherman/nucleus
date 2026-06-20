import AppKit
import ClipboardKit
import NucleusKit
import SwiftUI

struct ClipboardPickerView: View {
    let entries: [ClipboardEntry]
    let onSelect: (ClipboardEntry) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var highlightedID: UUID?
    @State private var confirmedSelectionID: UUID?
    @State private var isConfirmingSelection = false
    @FocusState private var searchFocused: Bool

    private let selectionConfirmationDelay: Duration = .milliseconds(420)

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
                .onKeyPress(.upArrow) {
                    moveHighlight(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveHighlight(by: 1)
                    return .handled
                }
                .onSubmit {
                    submitHighlightedSelection()
                }

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
        .onAppear {
            highlightedID = filteredEntries.first?.id
            searchFocused = true
        }
        .onChange(of: query) { _, _ in
            guard !isConfirmingSelection else { return }
            highlightedID = filteredEntries.first?.id
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
