import Foundation

public enum GoogleAccountAuthMode: String, Codable, Hashable, Sendable {
    case oauth
    case webSession
}

public struct GoogleAccount: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var email: String
    public var displayName: String
    public var avatarURL: String
    public var isPrimary: Bool
    public var isPrimaryNotesAccount: Bool
    public var authMode: GoogleAccountAuthMode

    public init(
        id: UUID = UUID(),
        email: String,
        displayName: String,
        avatarURL: String = "",
        isPrimary: Bool = false,
        isPrimaryNotesAccount: Bool = false,
        authMode: GoogleAccountAuthMode = .webSession
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isPrimary = isPrimary
        self.isPrimaryNotesAccount = isPrimaryNotesAccount
        self.authMode = authMode
    }

    public var usesOAuthAPI: Bool {
        authMode == .oauth
    }
}

public enum WorkspacePane: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case inbox
    case clipboard
    case notes
    case bills
    case calendar
    case media
    case terminal
    case accounts
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .inbox: return "Inbox"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes and Passwords"
        case .bills: return "Bills"
        case .calendar: return "Calendar"
        case .media: return "Music"
        case .terminal: return "Terminal"
        case .accounts: return "Accounts"
        case .settings: return "Settings"
        }
    }

    public var subtitle: String {
        switch self {
        case .dashboard: return "Summary, bills, and activity"
        case .inbox: return "Gmail across all accounts"
        case .clipboard: return "Recent clips and templates"
        case .notes: return "Markdown notes and password vault"
        case .bills: return "Monthly bills and payments"
        case .calendar: return "Schedule and video call links"
        case .media: return "Apple Music and AirPlay"
        case .terminal: return "tmux sessions and shell"
        case .accounts: return "Google identities"
        case .settings: return "Sync and notifications"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .inbox: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .bills: return "dollarsign.circle"
        case .calendar: return "calendar"
        case .media: return "music.note"
        case .terminal: return "terminal"
        case .accounts: return "person.crop.circle.badge.plus"
        case .settings: return "gearshape"
        }
    }

    public static let primaryWorkspaces: [WorkspacePane] = [.dashboard, .inbox, .clipboard, .notes, .bills, .calendar, .media, .terminal]
    public static let reorderableWorkspaces: [WorkspacePane] = primaryWorkspaces
    public static let defaultWorkspacePaneOrder: [WorkspacePane] = reorderableWorkspaces
    public static let utilityWorkspaces: [WorkspacePane] = [.settings, .accounts]

    public var isReorderableSidebarItem: Bool {
        Self.reorderableWorkspaces.contains(self)
    }
}

public enum ActivitySource: String, Codable, Sendable {
    case gmail
    case calendar
    case clipboard
    case notes
}

public struct ActivityItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var detail: String
    public var source: ActivitySource
    public var timestamp: Date
    public var accountEmail: String?

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        source: ActivitySource,
        timestamp: Date = Date(),
        accountEmail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.source = source
        self.timestamp = timestamp
        self.accountEmail = accountEmail
    }
}

public struct MailMessageSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var accountID: UUID
    public var threadID: String
    public var fromName: String
    public var fromEmail: String
    public var subject: String
    public var snippet: String
    public var receivedAt: Date
    public var isUnread: Bool

    public init(
        id: String,
        accountID: UUID,
        threadID: String,
        fromName: String,
        fromEmail: String,
        subject: String,
        snippet: String,
        receivedAt: Date,
        isUnread: Bool
    ) {
        self.id = id
        self.accountID = accountID
        self.threadID = threadID
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.subject = subject
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.isUnread = isUnread
    }
}

public struct CalendarEventSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var accountID: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var location: String
    public var attendees: [String]
    public var meetingLink: String?
    public var accountEmail: String
    public var isBirthday: Bool

    public init(
        id: String,
        accountID: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String = "",
        attendees: [String] = [],
        meetingLink: String? = nil,
        accountEmail: String,
        isBirthday: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.attendees = attendees
        self.meetingLink = meetingLink
        self.accountEmail = accountEmail
        self.isBirthday = isBirthday
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID
        case title
        case startDate
        case endDate
        case location
        case attendees
        case meetingLink
        case accountEmail
        case isBirthday
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        accountID = try container.decode(UUID.self, forKey: .accountID)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        attendees = try container.decodeIfPresent([String].self, forKey: .attendees) ?? []
        meetingLink = try container.decodeIfPresent(String.self, forKey: .meetingLink)
        accountEmail = try container.decode(String.self, forKey: .accountEmail)
        isBirthday = try container.decodeIfPresent(Bool.self, forKey: .isBirthday) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(title, forKey: .title)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(location, forKey: .location)
        try container.encode(attendees, forKey: .attendees)
        try container.encodeIfPresent(meetingLink, forKey: .meetingLink)
        try container.encode(accountEmail, forKey: .accountEmail)
        try container.encode(isBirthday, forKey: .isBirthday)
    }
}

public struct ClipboardEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var content: String
    public var contentType: String
    public var sourceApplication: String
    public var tags: [String]
    public var isPinned: Bool
    public var capturedAt: Date

    public init(
        id: UUID = UUID(),
        content: String,
        contentType: String = "text",
        sourceApplication: String = "Unknown",
        tags: [String] = [],
        isPinned: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.sourceApplication = sourceApplication
        self.tags = tags
        self.isPinned = isPinned
        self.capturedAt = capturedAt
    }
}

public struct NoteDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var markdown: String
    public var folder: NoteFolder
    public var updatedAt: Date
    public var driveFileID: String?

    public init(
        id: UUID = UUID(),
        title: String,
        markdown: String,
        folder: NoteFolder,
        updatedAt: Date = Date(),
        driveFileID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.folder = folder
        self.updatedAt = updatedAt
        self.driveFileID = driveFileID
    }
}

public enum NoteFolder: String, Codable, CaseIterable, Sendable {
    case notes = "Notes"
    case passwords = "Passwords"

    public var drivePath: String {
        "/Nucleus/\(rawValue)"
    }

    public var systemImage: String {
        switch self {
        case .notes: return "note.text"
        case .passwords: return "key"
        }
    }

    public var isSensitive: Bool {
        self == .passwords
    }

    public static func normalized(from rawValue: String) -> NoteFolder {
        if let folder = NoteFolder(rawValue: rawValue) {
            return folder
        }

        switch rawValue {
        case "Daily Notes", "Meeting Notes", "Clipboard Notes":
            return .notes
        case "Credentials":
            return .passwords
        default:
            return .notes
        }
    }
}

/// Configuration synced via iCloud CloudKit. OAuth tokens and Google content stay device-local.
public struct WindowLayoutState: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double
    public var originX: Double?
    public var originY: Double?
    /// NSScreen.frame.origin/size when saved — used to restore the same monitor.
    public var screenOriginX: Double?
    public var screenOriginY: Double?
    public var screenWidth: Double?
    public var screenHeight: Double?
    /// CGDirectDisplayID for the monitor when saved.
    public var displayID: UInt32?
    public var sidebarWidth: Double?
    public var notesListWidth: Double?

    public init(
        width: Double,
        height: Double,
        originX: Double? = nil,
        originY: Double? = nil,
        screenOriginX: Double? = nil,
        screenOriginY: Double? = nil,
        screenWidth: Double? = nil,
        screenHeight: Double? = nil,
        displayID: UInt32? = nil,
        sidebarWidth: Double? = nil,
        notesListWidth: Double? = nil
    ) {
        self.width = width
        self.height = height
        self.originX = originX
        self.originY = originY
        self.screenOriginX = screenOriginX
        self.screenOriginY = screenOriginY
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.displayID = displayID
        self.sidebarWidth = sidebarWidth
        self.notesListWidth = notesListWidth
    }

    /// Column widths synced via iCloud. Frame size and position stay on each Mac.
    public func cloudKitColumnWidths() -> WindowLayoutState {
        WindowLayoutState(
            width: 0,
            height: 0,
            sidebarWidth: sidebarWidth,
            notesListWidth: notesListWidth
        )
    }

    public mutating func mergeCloudKitColumnWidths(from remote: WindowLayoutState) {
        if let sidebarWidth = remote.sidebarWidth {
            self.sidebarWidth = sidebarWidth
        }
        if let notesListWidth = remote.notesListWidth {
            self.notesListWidth = notesListWidth
        }
    }
}

/// Configuration synced via iCloud CloudKit. OAuth tokens sync separately via iCloud Keychain when enabled.
public struct NucleusSyncedConfiguration: Codable, Hashable, Sendable {
    public static let currentVersion = 3
    public static let singletonRecordID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public var version: Int
    public var primaryAccountID: String?
    public var mailSyncInterval: TimeInterval
    public var mailNotificationSound: String
    public var mailNotificationSoundByAccount: [String: String]
    public var chatNotificationSound: String
    public var chatNotificationSoundByAccount: [String: String]
    public var selectedMailAccountID: String?
    public var selectedCalendarAccountID: String?
    public var selectedChatAccountID: String?
    public var emailNotificationsEnabled: Bool
    public var chatNotificationsEnabled: Bool
    public var calendarNotificationsEnabled: Bool
    public var selectedWorkspacePane: String?
    public var windowLayout: WindowLayoutState?
    public var clipboardSyncEnabled: Bool
    public var clipboardSaveToNotesEnabled: Bool
    public var iCloudKeychainTokenSyncEnabled: Bool
    public var billNotificationsEnabled: Bool
    public var billNotificationHour: Int
    public var billNotifySevenDaysBefore: Bool
    public var billNotifyThreeDaysBefore: Bool
    public var billNotifyOneDayBefore: Bool
    public var billNotifyOnDueDate: Bool
    public var updatedAt: Date

    public init(
        version: Int = NucleusSyncedConfiguration.currentVersion,
        primaryAccountID: String? = nil,
        mailSyncInterval: TimeInterval = 60,
        mailNotificationSound: String = "NucleusMail",
        mailNotificationSoundByAccount: [String: String] = [:],
        chatNotificationSound: String = "Funky",
        chatNotificationSoundByAccount: [String: String] = [:],
        selectedMailAccountID: String? = nil,
        selectedCalendarAccountID: String? = nil,
        selectedChatAccountID: String? = nil,
        emailNotificationsEnabled: Bool = true,
        chatNotificationsEnabled: Bool = true,
        calendarNotificationsEnabled: Bool = true,
        selectedWorkspacePane: String? = nil,
        windowLayout: WindowLayoutState? = nil,
        clipboardSyncEnabled: Bool = true,
        clipboardSaveToNotesEnabled: Bool = false,
        iCloudKeychainTokenSyncEnabled: Bool = true,
        billNotificationsEnabled: Bool = true,
        billNotificationHour: Int = 7,
        billNotifySevenDaysBefore: Bool = true,
        billNotifyThreeDaysBefore: Bool = true,
        billNotifyOneDayBefore: Bool = true,
        billNotifyOnDueDate: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.primaryAccountID = primaryAccountID
        self.mailSyncInterval = mailSyncInterval
        self.mailNotificationSound = mailNotificationSound
        self.mailNotificationSoundByAccount = mailNotificationSoundByAccount
        self.chatNotificationSound = chatNotificationSound
        self.chatNotificationSoundByAccount = chatNotificationSoundByAccount
        self.selectedMailAccountID = selectedMailAccountID
        self.selectedCalendarAccountID = selectedCalendarAccountID
        self.selectedChatAccountID = selectedChatAccountID
        self.emailNotificationsEnabled = emailNotificationsEnabled
        self.chatNotificationsEnabled = chatNotificationsEnabled
        self.calendarNotificationsEnabled = calendarNotificationsEnabled
        self.selectedWorkspacePane = selectedWorkspacePane
        self.windowLayout = windowLayout
        self.clipboardSyncEnabled = clipboardSyncEnabled
        self.clipboardSaveToNotesEnabled = clipboardSaveToNotesEnabled
        self.iCloudKeychainTokenSyncEnabled = iCloudKeychainTokenSyncEnabled
        self.billNotificationsEnabled = billNotificationsEnabled
        self.billNotificationHour = billNotificationHour
        self.billNotifySevenDaysBefore = billNotifySevenDaysBefore
        self.billNotifyThreeDaysBefore = billNotifyThreeDaysBefore
        self.billNotifyOneDayBefore = billNotifyOneDayBefore
        self.billNotifyOnDueDate = billNotifyOnDueDate
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        primaryAccountID = try container.decodeIfPresent(String.self, forKey: .primaryAccountID)
        mailSyncInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .mailSyncInterval) ?? 60
        mailNotificationSound = try container.decodeIfPresent(String.self, forKey: .mailNotificationSound) ?? "NucleusMail"
        mailNotificationSoundByAccount = try container.decodeIfPresent([String: String].self, forKey: .mailNotificationSoundByAccount) ?? [:]
        chatNotificationSound = try container.decodeIfPresent(String.self, forKey: .chatNotificationSound) ?? "Funky"
        chatNotificationSoundByAccount = try container.decodeIfPresent([String: String].self, forKey: .chatNotificationSoundByAccount) ?? [:]
        selectedMailAccountID = try container.decodeIfPresent(String.self, forKey: .selectedMailAccountID)
        selectedCalendarAccountID = try container.decodeIfPresent(String.self, forKey: .selectedCalendarAccountID)
        selectedChatAccountID = try container.decodeIfPresent(String.self, forKey: .selectedChatAccountID)
        emailNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .emailNotificationsEnabled) ?? true
        chatNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatNotificationsEnabled) ?? true
        calendarNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarNotificationsEnabled) ?? true
        selectedWorkspacePane = try container.decodeIfPresent(String.self, forKey: .selectedWorkspacePane)
        windowLayout = try container.decodeIfPresent(WindowLayoutState.self, forKey: .windowLayout)
        clipboardSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardSyncEnabled) ?? true
        clipboardSaveToNotesEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardSaveToNotesEnabled) ?? false
        iCloudKeychainTokenSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .iCloudKeychainTokenSyncEnabled) ?? true
        billNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .billNotificationsEnabled) ?? true
        billNotificationHour = try container.decodeIfPresent(Int.self, forKey: .billNotificationHour) ?? 7
        billNotifySevenDaysBefore = try container.decodeIfPresent(Bool.self, forKey: .billNotifySevenDaysBefore) ?? true
        billNotifyThreeDaysBefore = try container.decodeIfPresent(Bool.self, forKey: .billNotifyThreeDaysBefore) ?? true
        billNotifyOneDayBefore = try container.decodeIfPresent(Bool.self, forKey: .billNotifyOneDayBefore) ?? true
        billNotifyOnDueDate = try container.decodeIfPresent(Bool.self, forKey: .billNotifyOnDueDate) ?? true
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public extension NucleusSyncedConfiguration {
    var billDueReminderConfiguration: BillDueReminderConfiguration {
        BillDueReminderConfiguration(
            enabled: billNotificationsEnabled,
            hour: billNotificationHour,
            notifySevenDaysBefore: billNotifySevenDaysBefore,
            notifyThreeDaysBefore: billNotifyThreeDaysBefore,
            notifyOneDayBefore: billNotifyOneDayBefore,
            notifyOnDueDate: billNotifyOnDueDate
        )
    }
}

public enum NucleusFormatters {
    public static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    public static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    public static let dayHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM yyyy"
        return formatter
    }()

    public static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }()

    public static func currencyString(_ amount: Double, currencyCode: String = Locale.current.currency?.identifier ?? "AUD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode.uppercased()
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode.uppercased()) \(String(format: "%.2f", amount))"
    }
}

public enum ExternalLinkPolicy {
    public static let externalHosts: Set<String> = [
        "docs.google.com",
        "drive.google.com",
        "atlassian.net",
        "github.com",
        "gitlab.com",
        "zoom.us",
        "teams.microsoft.com",
        "meet.google.com",
    ]

    public static func shouldOpenExternally(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if externalHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }
        return false
    }
}
