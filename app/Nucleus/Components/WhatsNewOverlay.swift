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
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(release.headline)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if release.sections.isEmpty {
                            Text("This update includes improvements and fixes across mail, calendar, and workspace sync.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(release.sections) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(section.title)
                                        .font(.headline)
                                    ForEach(section.items, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.subheadline)
                                                .padding(.top, 2)
                                            Text(item)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 360)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(28)
            }
            .frame(width: 520)
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
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("What's New")
                    .font(.title.bold())
                Text("Nucleus \(release.version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
