import Foundation
import NucleusKit

enum MarketingScreenshotMode {
    private static let env = ProcessInfo.processInfo.environment

    static var isActive: Bool {
        env["NUCLEUS_MARKETING_SCREENSHOT"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-marketingScreenshotMode")
    }

    static var pane: WorkspacePane? {
        guard isActive else { return nil }
        if let raw = env["NUCLEUS_MARKETING_SCREENSHOT_PANE"] {
            return WorkspacePane(rawValue: raw)
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-marketingScreenshotPane"),
           index + 1 < ProcessInfo.processInfo.arguments.count {
            return WorkspacePane(rawValue: ProcessInfo.processInfo.arguments[index + 1])
        }
        return nil
    }

    static var exportPath: String? {
        guard isActive else { return nil }
        if let path = env["NUCLEUS_MARKETING_SCREENSHOT_EXPORT"], !path.isEmpty {
            return path
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-marketingScreenshotExport"),
           index + 1 < ProcessInfo.processInfo.arguments.count {
            return ProcessInfo.processInfo.arguments[index + 1]
        }
        return nil
    }

    static func demoBadgeCount(for pane: WorkspacePane) -> Int? {
        switch pane {
        case .inbox: return 3
        case .clipboard: return 12
        case .bills: return 4
        case .terminal: return 2
        default: return nil
        }
    }

    static func demoNoteBadges(for pane: WorkspacePane) -> (notes: Int, passwords: Int)? {
        guard pane == .notes else { return nil }
        return (notes: 2, passwords: 3)
    }

    static var showsMusicPlayingBadge: Bool {
        pane == .media
    }
}
