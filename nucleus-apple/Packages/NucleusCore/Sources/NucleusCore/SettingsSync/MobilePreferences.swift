import Foundation

public enum MobileWorkspaceTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case mail
    case calendar
    case chat
    case notes
    case settings

    public var id: String { rawValue }

    /// Tabs shown in the iOS companion app (Mail, Calendar, and Chat are macOS-only).
    public static let iosTabs: [MobileWorkspaceTab] = [.notes, .settings]

    public var title: String {
        switch self {
        case .mail: return "Mail"
        case .calendar: return "Calendar"
        case .chat: return "Chat"
        case .notes: return "Notes"
        case .settings: return "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .mail: return "tray.full"
        case .calendar: return "calendar"
        case .chat: return "message"
        case .notes: return "note.text"
        case .settings: return "gearshape"
        }
    }

    public static func normalizedForIOS(_ tab: MobileWorkspaceTab) -> MobileWorkspaceTab {
        iosTabs.contains(tab) ? tab : .notes
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
        selectedTab: MobileWorkspaceTab = .notes,
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
