import Foundation

public enum MobileWorkspaceTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case dashboard
    case notes
    case passwords
    case bills
    case settings
    case mail
    case calendar
    case chat

    public var id: String { rawValue }

    /// Primary tabs in the iOS / iPadOS bottom bar.
    public static let iosMainTabs: [MobileWorkspaceTab] = [.dashboard, .notes, .passwords, .bills, .calendar]

    /// Includes every workspace tab reachable on iOS, including settings presented outside the tab bar.
    public static let iosTabs: [MobileWorkspaceTab] = iosMainTabs + [.settings]

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .notes: return "Notes"
        case .passwords: return "Passwords"
        case .bills: return "Bills"
        case .settings: return "Settings"
        case .mail: return "Mail"
        case .calendar: return "Calendar"
        case .chat: return "Chat"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .notes: return "note.text"
        case .passwords: return "key.fill"
        case .bills: return "dollarsign.circle"
        case .settings: return "gearshape"
        case .mail: return "tray.full"
        case .calendar: return "calendar"
        case .chat: return "message"
        }
    }

    public static func normalizedForIOS(_ tab: MobileWorkspaceTab) -> MobileWorkspaceTab {
        switch tab {
        case .mail, .chat, .settings:
            return .dashboard
        default:
            return iosMainTabs.contains(tab) ? tab : .dashboard
        }
    }
}

public struct MobilePreferences: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var selectedTab: MobileWorkspaceTab
    public var selectedMailAccountID: String?
    public var selectedCalendarAccountID: String?
    public var selectedChatAccountID: String?
    public var primaryNotesAccountID: String?
    public var updatedAt: Date

    public init(
        version: Int = MobilePreferences.currentVersion,
        selectedTab: MobileWorkspaceTab = .dashboard,
        selectedMailAccountID: String? = nil,
        selectedCalendarAccountID: String? = nil,
        selectedChatAccountID: String? = nil,
        primaryNotesAccountID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.selectedTab = selectedTab
        self.selectedMailAccountID = selectedMailAccountID
        self.selectedCalendarAccountID = selectedCalendarAccountID
        self.selectedChatAccountID = selectedChatAccountID
        self.primaryNotesAccountID = primaryNotesAccountID
        self.updatedAt = updatedAt
    }
}
