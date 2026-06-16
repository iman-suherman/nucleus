import AppKit
import Foundation
import NucleusKit

@MainActor
enum DockBadgeController {
    static func update(mailUnread: Int, chatUnread: Int) {
        if mailUnread == 0 && chatUnread == 0 {
            NSApp.dockTile.badgeLabel = nil
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.display()
            return
        }

        NSApp.dockTile.badgeLabel = nil
        let tileSize = NSApp.dockTile.size
        let contentView = NSView(frame: NSRect(origin: .zero, size: tileSize))

        if let icon = NSApp.applicationIconImage {
            let iconView = NSImageView(frame: contentView.bounds)
            iconView.image = icon
            iconView.imageScaling = .scaleProportionallyUpOrDown
            contentView.addSubview(iconView)
        }

        if mailUnread > 0 {
            contentView.addSubview(
                makeBadge(count: mailUnread, color: NSColor.systemBlue, alignment: .leading)
            )
        }

        if chatUnread > 0 {
            contentView.addSubview(
                makeBadge(count: chatUnread, color: chatBadgeColor, alignment: .trailing)
            )
        }

        NSApp.dockTile.contentView = contentView
        NSApp.dockTile.display()
    }

    private static let chatBadgeColor = NSColor(
        red: 129 / 255,
        green: 201 / 255,
        blue: 149 / 255,
        alpha: 1
    )

    private enum BadgeAlignment {
        case leading
        case trailing
    }

    private static func makeBadge(count: Int, color: NSColor, alignment: BadgeAlignment) -> NSView {
        let tileSize = NSApp.dockTile.size
        let metrics = badgeMetrics(for: tileSize)

        let label = NSTextField(labelWithString: "\(count)")
        label.font = .systemFont(ofSize: metrics.fontSize, weight: .bold)
        label.textColor = .white
        label.alignment = .center

        let width = max(metrics.height, label.intrinsicContentSize.width + metrics.horizontalPadding * 2)
        let x: CGFloat = switch alignment {
        case .leading: tileSize.width * 0.50
        case .trailing: tileSize.width - width - tileSize.width * 0.03
        }

        let container = NSView(
            frame: NSRect(x: x, y: tileSize.height * 0.05, width: width, height: metrics.height)
        )
        container.wantsLayer = true
        container.layer?.backgroundColor = color.cgColor
        container.layer?.cornerRadius = metrics.height / 2

        label.frame = NSRect(x: 0, y: 2, width: width, height: metrics.height - 4)
        container.addSubview(label)
        return container
    }

    private static func badgeMetrics(for tileSize: NSSize) -> (
        height: CGFloat,
        fontSize: CGFloat,
        horizontalPadding: CGFloat
    ) {
        // Scale with the dock tile so counts stay readable at every Dock icon size.
        let height = max(26, tileSize.height * 0.24)
        let fontSize = max(16, height * 0.56)
        let horizontalPadding = max(9, height * 0.32)
        return (height, fontSize, horizontalPadding)
    }
}

enum ChromeLauncher {
    static func open(url: URL) {
        let chromePaths = [
            "/Applications/Google Chrome.app",
            "/Applications/Google Chrome Canary.app",
        ]

        for path in chromePaths where FileManager.default.fileExists(atPath: path) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: path), configuration: configuration)
            return
        }

        NSWorkspace.shared.open(url)
    }
}
