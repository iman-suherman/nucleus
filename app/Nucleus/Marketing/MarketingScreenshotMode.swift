import Foundation
import NucleusKit

enum MarketingScreenshotMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-marketingScreenshotMode")
    }

    static var pane: WorkspacePane? {
        guard isActive,
              let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-marketingScreenshotPane"),
              index + 1 < ProcessInfo.processInfo.arguments.count else {
            return nil
        }
        return WorkspacePane(rawValue: ProcessInfo.processInfo.arguments[index + 1])
    }

    static var exportPath: String? {
        guard isActive,
              let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-marketingScreenshotExport"),
              index + 1 < ProcessInfo.processInfo.arguments.count else {
            return nil
        }
        return ProcessInfo.processInfo.arguments[index + 1]
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
