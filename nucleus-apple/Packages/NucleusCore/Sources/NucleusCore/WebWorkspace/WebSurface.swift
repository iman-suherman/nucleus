import Foundation

public enum WebSurface: String, Hashable, Sendable, CaseIterable {
    case mail
    case chat
    case calendar

    public var workspacePane: WorkspacePane {
        switch self {
        case .mail: return .inbox
        case .chat: return .chat
        case .calendar: return .calendar
        }
    }
}
