import SwiftUI

struct ClipboardPasswordSuggestion: Identifiable, Equatable {
    let id: UUID
    let password: String
    let sourceApplication: String
    let capturedAt: Date
    let reason: String
}

struct ClipboardPasswordSuggestionOverlay: View {
    let suggestion: ClipboardPasswordSuggestion
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    Text("Nucleus noticed a password-like value on your clipboard from \(suggestion.sourceApplication).")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledContent("Detected value") {
                        Text(maskedPassword)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Save creates a Passwords note with the value filled in. You can add the title, URL, username, and email before saving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Not Now", action: onDismiss)
                    Spacer()
                    Button("Save to Passwords", action: onSave)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
            .frame(width: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(120)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Save to Passwords?")
                    .font(.title3.bold())
                Text("Intelligent clipboard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var maskedPassword: String {
        let value = suggestion.password
        guard value.count > 4 else { return String(repeating: "•", count: value.count) }
        let suffix = value.suffix(2)
        return String(repeating: "•", count: min(value.count - 2, 12)) + suffix
    }
}
