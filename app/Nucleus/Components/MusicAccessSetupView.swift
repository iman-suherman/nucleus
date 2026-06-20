import AppKit
import MusicKit
import SwiftUI

struct MusicAccessSetupView: View {
    @ObservedObject var controller: MediaController
    @State private var isSettingUp = false

    private var access: MusicAccessSnapshot {
        controller.musicAccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(Color.accentColor)
                Text("Music Access")
                    .font(.headline)
                Spacer()
                if access.isFullyReady {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text("Nucleus needs two macOS permissions to search and play Apple Music.")
                .font(.caption)
                .foregroundStyle(.secondary)

            permissionRow(
                title: "Media & Apple Music",
                detail: "Search the catalog and play tracks inside Nucleus.",
                isReady: access.isCatalogReady,
                status: catalogStatusLabel
            ) {
                if access.catalogAccess == .denied || access.catalogAccess == .restricted {
                    controller.openMusicAccessSettings(.mediaAndAppleMusic)
                } else {
                    Task { await runSetup() }
                }
            }

            permissionRow(
                title: "Control Music.app",
                detail: "Play songs from your library and skip tracks via the Music app.",
                isReady: access.isAutomationReady,
                status: automationStatusLabel
            ) {
                if access.musicAutomation == .denied {
                    controller.openMusicAccessSettings(.automation)
                } else if access.musicAutomation == .musicAppMissing {
                    openMusicAppStore()
                } else {
                    Task { await runSetup() }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await runSetup() }
                } label: {
                    if isSettingUp {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(access.isFullyReady ? "Recheck Access" : "Set Up Access")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSettingUp)

                if !access.isFullyReady {
                    Button("Open Settings") {
                        if !access.isCatalogReady {
                            controller.openMusicAccessSettings(.mediaAndAppleMusic)
                        } else {
                            controller.openMusicAccessSettings(.automation)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(access.isFullyReady ? 0 : 0.25), lineWidth: 1)
        )
    }

    private var catalogStatusLabel: String {
        switch access.catalogAccess {
        case .granted:
            return "Allowed"
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied — open System Settings"
        case .restricted:
            return "Restricted on this Mac"
        }
    }

    private var automationStatusLabel: String {
        switch access.musicAutomation {
        case .granted:
            return "Allowed"
        case .denied:
            return "Denied — enable Nucleus → Music in Automation"
        case .musicAppMissing:
            return "Music.app not installed"
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        isReady: Bool,
        status: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReady ? .green : .secondary)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(isReady ? .secondary : Color.orange)
            }

            Spacer(minLength: 8)

            if !isReady {
                Button("Fix") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func runSetup() async {
        isSettingUp = true
        defer { isSettingUp = false }
        await controller.setupMusicAccess()
    }

    private func openMusicAppStore() {
        guard let url = URL(string: "macappstore://apps.apple.com/app/id1108187390") else { return }
        NSWorkspace.shared.open(url)
    }
}
