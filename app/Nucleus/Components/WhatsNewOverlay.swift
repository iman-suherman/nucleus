import SwiftUI

struct WhatsNewOverlay: View {
    let release: AppReleaseNotes
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 18)

                Divider()

                ScrollView {
                    ReleaseNotesDetailView(release: release)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                }
                .frame(maxHeight: 460)

                Divider()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(24)
            }
            .frame(width: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(110)
    }

    private var header: some View {
        HStack(spacing: 16) {
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                    .frame(width: 56, height: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("What's New")
                    .font(.title2.bold())
                Text("Nucleus \(release.version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
