import AppKit
import Foundation
import NucleusKit

@MainActor
enum DockBadgeController {
    private static let billBadgeColor = NSColor(
        red: 129 / 255,
        green: 201 / 255,
        blue: 149 / 255,
        alpha: 1
    )

    static func update(mailUnread: Int, chatUnread: Int, billsDueSoon: Int) {
        if mailUnread == 0 && chatUnread == 0 && billsDueSoon == 0 {
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

        if billsDueSoon > 0 {
            contentView.addSubview(
                makeBadge(count: billsDueSoon, color: billBadgeColor, corner: .topLeading)
            )
        }

        if mailUnread > 0 {
            contentView.addSubview(
                makeBadge(count: mailUnread, color: .systemRed, corner: .topTrailing, scale: 1.25)
            )
        }

        if chatUnread > 0 {
            contentView.addSubview(
                makeBadge(count: chatUnread, color: .systemBlue, corner: .bottomTrailing, scale: 1.1)
            )
        }

        NSApp.dockTile.contentView = contentView
        NSApp.dockTile.display()
    }

    private enum BadgeCorner {
        case topLeading
        case topTrailing
        case bottomTrailing
    }

    private static func makeBadge(
        count: Int,
        color: NSColor,
        corner: BadgeCorner,
        scale: CGFloat = 1
    ) -> NSView {
        let tileSize = NSApp.dockTile.size
        let metrics = badgeMetrics(for: tileSize, scale: scale)
        let inset = tileSize.width * 0.03

        let label = NSTextField(labelWithString: "\(count)")
        label.font = .systemFont(ofSize: metrics.fontSize, weight: .bold)
        label.textColor = .white
        label.alignment = .center

        let width = max(metrics.height, label.intrinsicContentSize.width + metrics.horizontalPadding * 2)
        let x: CGFloat = switch corner {
        case .topLeading:
            inset
        case .topTrailing, .bottomTrailing:
            tileSize.width - width - inset
        }
        let y: CGFloat = switch corner {
        case .topLeading, .topTrailing:
            tileSize.height - metrics.height - inset
        case .bottomTrailing:
            inset
        }

        let container = NSView(
            frame: NSRect(x: x, y: y, width: width, height: metrics.height)
        )
        container.wantsLayer = true
        container.layer?.backgroundColor = color.cgColor
        container.layer?.cornerRadius = metrics.height / 2

        label.frame = NSRect(x: 0, y: 2, width: width, height: metrics.height - 4)
        container.addSubview(label)
        return container
    }

    private static func badgeMetrics(
        for tileSize: NSSize,
        scale: CGFloat = 1
    ) -> (
        height: CGFloat,
        fontSize: CGFloat,
        horizontalPadding: CGFloat
    ) {
        // Scale with the dock tile so counts stay readable at every Dock icon size.
        let height = max(32, tileSize.height * 0.30) * scale
        let fontSize = max(18, height * 0.58)
        let horizontalPadding = max(11, height * 0.34)
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
