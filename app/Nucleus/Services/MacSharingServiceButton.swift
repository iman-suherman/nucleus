import AppKit
import SwiftUI

struct MacSharingServiceButton: View {
    let items: [Any]
    var helpText: String = "Share"

    var body: some View {
        MacSharingServiceButtonRepresentable(items: items)
            .frame(width: 22, height: 22)
            .help(helpText)
            .accessibilityLabel(helpText)
    }
}

private struct MacSharingServiceButtonRepresentable: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(
            systemSymbolName: "square.and.arrow.up",
            accessibilityDescription: "Share"
        )
        let button = NSButton(image: image ?? NSImage(), target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = NSColor.secondaryLabelColor
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.items = items
        button.isEnabled = !items.isEmpty
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items)
    }

    final class Coordinator: NSObject {
        var items: [Any]
        weak var button: NSButton?

        init(items: [Any]) {
            self.items = items
        }

        @objc func share(_ sender: NSButton) {
            guard !items.isEmpty else { return }
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}

enum DashboardNewsSharePayload {
    static func items(
        headline: DashboardNewsHeadline,
        enrichment: DashboardNewsEnrichment,
        displayTitle: String
    ) -> [Any] {
        var items: [Any] = []

        var text = displayTitle
        if !enrichment.readerSummary.isEmpty {
            text += "\n\n\(enrichment.readerSummary)"
        }
        items.append(text as NSString)

        if let link = headline.link {
            items.append(link as NSURL)
        }

        return items
    }
}
