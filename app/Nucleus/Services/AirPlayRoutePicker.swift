import AVKit
import AppKit
import NucleusKit
import SwiftUI

enum CatalogAirPlayHint {
    static let menuMessage =
        "This track streams inside Nucleus. AirPlay here routes Music.app only — library playback or Music.app can reach speakers."
    static let cardMessage =
        "AirPlay routes through Music.app. Catalog streaming plays inside Nucleus and won't move to HomePods from this menu."
    static let tooltip =
        "Catalog track — AirPlay uses Music.app. Play via Music.app for speaker output."
}

struct MediaAirPlayButton: View {
    var compact = false

    @ObservedObject private var controller = MediaController.shared

    var body: some View {
        Group {
            switch controller.playbackSource {
            case .localPlayer:
                AirPlayRoutePickerButton(compact: compact)
            case .musicApp:
                MusicAppAirPlayMenuButton(compact: compact)
            }
        }
    }
}

struct AirPlayRoutePickerButton: View {
    var compact = false

    var body: some View {
        AirPlayRoutePickerRepresentable()
            .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
            .help("Choose AirPlay output")
            .accessibilityLabel("Choose AirPlay output")
    }
}

private struct MusicAppAirPlayMenuButton: View {
    var compact = false

    @ObservedObject private var controller = MediaController.shared
    @State private var devices: [(name: String, isSelected: Bool)] = []
    @State private var loadError: String?

    var body: some View {
        Menu {
            Group {
                if controller.isCatalogStreamPlayback {
                    Text(CatalogAirPlayHint.menuMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Play via Music.app for AirPlay…") {
                        controller.replayActiveTrackViaMusicApp()
                        refreshDevices()
                    }
                    Divider()
                }

                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if controller.musicAccess.musicAutomation == .denied {
                        Button("Open Automation Settings…") {
                            controller.openMusicAccessSettings(.automation)
                        }
                    } else {
                        Button("Allow Music Control…") {
                            Task { await controller.setupMusicAccess() }
                        }
                    }
                } else if devices.isEmpty {
                    Text("No AirPlay devices found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(devices, id: \.name) { device in
                        Button {
                            controller.selectAirPlayDevice(named: device.name)
                            refreshDevices()
                        } label: {
                            if device.isSelected {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
            }
            .onAppear(perform: refreshDevices)
        } label: {
            Image(systemName: "airplayaudio")
                .font(compact ? .caption.weight(.semibold) : .title3)
                .foregroundStyle(devices.contains(where: \.isSelected) ? Color.accentColor : .primary)
                .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
        }
        .menuStyle(.borderlessButton)
        .help(airPlayHelp)
        .accessibilityLabel("Choose AirPlay output")
        .disabled(!controller.isMusicAppAvailable)
        .onAppear(perform: refreshDevices)
    }

    private var airPlayHelp: String {
        if controller.isCatalogStreamPlayback {
            return CatalogAirPlayHint.tooltip
        }
        return loadError ?? "Choose AirPlay output"
    }

    private func refreshDevices() {
        controller.refreshMusicAccess()
        let result = MusicAppScriptController.fetchAirPlayDevices()
        devices = result.devices
        loadError = result.errorMessage
    }
}

private struct AirPlayRoutePickerRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.delegate = context.coordinator
        return picker
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {}
}
