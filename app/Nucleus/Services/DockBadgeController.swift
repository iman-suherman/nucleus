import NucleusKit
import AppKit
import Foundation

enum DockBadgeController {
    static func update(unreadCount: Int) {
        NSApp.dockTile.badgeLabel = unreadCount > 0 ? "\(unreadCount)" : nil
        NSApp.dockTile.display()
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
