import AVKit
import AppKit
import SwiftUI

struct AirPlayRoutePickerButton: View {
    var body: some View {
        AirPlayRoutePickerRepresentable()
            .frame(width: 28, height: 28)
            .help("Choose AirPlay output")
            .accessibilityLabel("Choose AirPlay output")
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
