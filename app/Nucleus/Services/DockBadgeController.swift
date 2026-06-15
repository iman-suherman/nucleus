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
        let label = NSTextField(labelWithString: "\(count)")
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.alignment = .center

        let horizontalPadding: CGFloat = 6
        let height: CGFloat = 18
        let width = max(height, label.intrinsicContentSize.width + horizontalPadding * 2)
        let tileSize = NSApp.dockTile.size
        let x: CGFloat = switch alignment {
        case .leading: tileSize.width * 0.54
        case .trailing: tileSize.width - width - tileSize.width * 0.04
        }

        let container = NSView(frame: NSRect(x: x, y: tileSize.height * 0.08, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = color.cgColor
        container.layer?.cornerRadius = height / 2

        label.frame = NSRect(x: 0, y: 1, width: width, height: height - 2)
        container.addSubview(label)
        return container
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
