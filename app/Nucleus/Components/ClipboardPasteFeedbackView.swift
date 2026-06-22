import SwiftUI

struct ClipboardPasteFeedbackView: View {
    let content: String

    private var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 280 else { return trimmed }
        return String(trimmed.prefix(277)) + "…"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text("Copied to clipboard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(preview)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 420, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.42),
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.06),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
