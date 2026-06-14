import Foundation
import NucleusKit
import SwiftData

@Model
public final class GoogleAccountRecord {
    @Attribute(.unique) public var id: UUID
    public var email: String
    public var displayName: String
    public var avatarURL: String
    public var isPrimary: Bool
    public var isPrimaryNotesAccount: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        email: String,
        displayName: String,
        avatarURL: String = "",
        isPrimary: Bool = false,
        isPrimaryNotesAccount: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isPrimary = isPrimary
        self.isPrimaryNotesAccount = isPrimaryNotesAccount
        self.createdAt = createdAt
    }

    public var model: GoogleAccount {
        GoogleAccount(
            id: id,
            email: email,
            displayName: displayName,
            avatarURL: avatarURL,
            isPrimary: isPrimary,
            isPrimaryNotesAccount: isPrimaryNotesAccount
        )
    }

    public func apply(_ account: GoogleAccount) {
        email = account.email
        displayName = account.displayName
        avatarURL = account.avatarURL
        isPrimary = account.isPrimary
        isPrimaryNotesAccount = account.isPrimaryNotesAccount
    }
}

@Model
public final class ClipboardItemRecord {
    @Attribute(.unique) public var id: UUID
    public var content: String
    public var contentType: String
    public var sourceApplication: String
    public var tagsCSV: String
    public var isPinned: Bool
    public var capturedAt: Date

    public init(
        id: UUID = UUID(),
        content: String,
        contentType: String = "text",
        sourceApplication: String = "Unknown",
        tagsCSV: String = "",
        isPinned: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.sourceApplication = sourceApplication
        self.tagsCSV = tagsCSV
        self.isPinned = isPinned
        self.capturedAt = capturedAt
    }

    public var tags: [String] {
        get {
            tagsCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        set {
            tagsCSV = newValue.joined(separator: ",")
        }
    }

    public var entry: ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: content,
            contentType: contentType,
            sourceApplication: sourceApplication,
            tags: tags,
            isPinned: isPinned,
            capturedAt: capturedAt
        )
    }
}

@Model
public final class CalendarEventRecord {
    @Attribute(.unique) public var id: String
    public var accountID: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var location: String
    public var attendeesCSV: String
    public var meetingLink: String?
    public var accountEmail: String

    public init(
        id: String,
        accountID: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String = "",
        attendeesCSV: String = "",
        meetingLink: String? = nil,
        accountEmail: String
    ) {
        self.id = id
        self.accountID = accountID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.attendeesCSV = attendeesCSV
        self.meetingLink = meetingLink
        self.accountEmail = accountEmail
    }

    public var attendees: [String] {
        get {
            attendeesCSV.split(separator: ";").map(String.init).filter { !$0.isEmpty }
        }
        set {
            attendeesCSV = newValue.joined(separator: ";")
        }
    }

    public var summary: CalendarEventSummary {
        CalendarEventSummary(
            id: id,
            accountID: accountID,
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location,
            attendees: attendees,
            meetingLink: meetingLink,
            accountEmail: accountEmail
        )
    }
}

@Model
public final class ActivityNotificationRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var detail: String
    public var sourceRaw: String
    public var timestamp: Date
    public var accountEmail: String?

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        sourceRaw: String,
        timestamp: Date = Date(),
        accountEmail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.sourceRaw = sourceRaw
        self.timestamp = timestamp
        self.accountEmail = accountEmail
    }

    public var source: ActivitySource {
        ActivitySource(rawValue: sourceRaw) ?? .gmail
    }

    public var item: ActivityItem {
        ActivityItem(
            id: id,
            title: title,
            detail: detail,
            source: source,
            timestamp: timestamp,
            accountEmail: accountEmail
        )
    }
}

@Model
public final class NoteRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var markdown: String
    public var folderRaw: String
    public var updatedAt: Date
    public var driveFileID: String?

    public init(
        id: UUID = UUID(),
        title: String,
        markdown: String,
        folderRaw: String,
        updatedAt: Date = Date(),
        driveFileID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.folderRaw = folderRaw
        self.updatedAt = updatedAt
        self.driveFileID = driveFileID
    }

    public var folder: NoteFolder {
        NoteFolder(rawValue: folderRaw) ?? .notes
    }

    public var document: NoteDocument {
        NoteDocument(
            id: id,
            title: title,
            markdown: markdown,
            folder: folder,
            updatedAt: updatedAt,
            driveFileID: driveFileID
        )
    }
}

@Model
public final class MailMessageRecord {
    @Attribute(.unique) public var id: String
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

    public var summary: MailMessageSummary {
        MailMessageSummary(
            id: id,
            accountID: accountID,
            threadID: threadID,
            fromName: fromName,
            fromEmail: fromEmail,
            subject: subject,
            snippet: snippet,
            receivedAt: receivedAt,
            isUnread: isUnread
        )
    }
}
