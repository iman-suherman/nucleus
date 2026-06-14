import NucleusKit
import SwiftUI

struct ClipboardWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Search clips…", text: $viewModel.clipboardSearchQuery)
                    .textFieldStyle(.roundedBorder)
                Text("\(viewModel.filteredClipboardEntries().count) items")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            List {
                ForEach(viewModel.filteredClipboardEntries()) { entry in
                    ClipboardRow(entry: entry) {
                        viewModel.toggleClipboardPin(entry)
                    } saveToNotes: {
                        Task { await viewModel.saveClipboardToNote(entry) }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let togglePin: () -> Void
    let saveToNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .lineLimit(4)
                .textSelection(.enabled)

            HStack {
                ForEach(entry.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
                Spacer()
                Button(entry.isPinned ? "Unpin" : "Pin", action: togglePin)
                    .buttonStyle(.borderless)
                Button("Save to Note", action: saveToNotes)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }
}
