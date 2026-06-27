import NucleusCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct WhatsNewOverlay: View {
    let release: AppReleaseNotes
    let onContinue: () -> Void

    public init(release: AppReleaseNotes, onContinue: @escaping () -> Void) {
        self.release = release
        self.onContinue = onContinue
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 18)

                Divider()

                ScrollView {
                    ReleaseNotesDetailView(release: release)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }

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
            .frame(maxWidth: 560, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(110)
    }

    private var header: some View {
        HStack(spacing: 16) {
            appIcon
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("What's New")
                    .font(.title2.bold())
                Text("Nucleus \(release.version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var appIcon: some View {
#if canImport(UIKit)
        if UIImage(named: "AppLogo") != nil {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            fallbackAppIcon
        }
#else
        fallbackAppIcon
#endif
    }

    private var fallbackAppIcon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 24))
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.blue.opacity(0.12))
    }
}
