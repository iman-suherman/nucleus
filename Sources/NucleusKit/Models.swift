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
    case inbox
    case calendar
    case chat
    case clipboard
    case notes
    case notifications
    case accounts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .chat: return "Chat"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .notifications: return "Notifications"
        case .accounts: return "Accounts"
        }
    }

    public var subtitle: String {
        switch self {
        case .inbox: return "Gmail across all accounts"
        case .calendar: return "Google Calendar in Nucleus"
        case .chat: return "Google Chat messages"
        case .clipboard: return "Recent clips and templates"
        case .notes: return "Markdown knowledge base"
        case .notifications: return "Activity feed"
        case .accounts: return "Google identities"
        }
    }

    public var icon: String {
        switch self {
        case .inbox: return "tray.full"
        case .calendar: return "calendar"
        case .chat: return "message"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .notifications: return "bell"
        case .accounts: return "person.crop.circle.badge.plus"
        }
    }

    public static let primaryWorkspaces: [WorkspacePane] = [.inbox, .calendar, .chat, .clipboard]
    public static let utilityWorkspaces: [WorkspacePane] = [.notifications, .accounts]
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

    public init(
        id: String,
        accountID: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String = "",
        attendees: [String] = [],
        meetingLink: String? = nil,
        accountEmail: String
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
    case dailyNotes = "Daily Notes"
    case meetingNotes = "Meeting Notes"
    case clipboardNotes = "Clipboard Notes"

    public var drivePath: String {
        "/Nucleus/\(rawValue)"
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
