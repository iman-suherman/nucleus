import AVKit
import AppKit
import NucleusKit
import SwiftUI

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

    var body: some View {
        Menu {
            Group {
                if devices.isEmpty {
                    Button("No AirPlay devices found") {}
                        .disabled(true)
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
        .help("Choose AirPlay output")
        .accessibilityLabel("Choose AirPlay output")
        .disabled(!controller.isMusicAppAvailable)
        .onAppear(perform: refreshDevices)
    }

    private func refreshDevices() {
        devices = MusicAppScriptController.fetchAirPlayDevices()
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
