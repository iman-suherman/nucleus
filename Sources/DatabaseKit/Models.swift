import Foundation
import NucleusKit
import SwiftData

@Model
public final class GoogleAccountRecord {
    public var id: UUID = UUID()
    public var email: String = ""
    public var displayName: String = ""
    public var avatarURL: String = ""
    public var isPrimary: Bool = false
    public var isPrimaryNotesAccount: Bool = false
    public var authMode: String = GoogleAccountAuthMode.webSession.rawValue
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        email: String,
        displayName: String,
        avatarURL: String = "",
        isPrimary: Bool = false,
        isPrimaryNotesAccount: Bool = false,
        authMode: String = GoogleAccountAuthMode.webSession.rawValue,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isPrimary = isPrimary
        self.isPrimaryNotesAccount = isPrimaryNotesAccount
        self.authMode = authMode
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    public var model: GoogleAccount {
        GoogleAccount(
            id: id,
            email: email,
            displayName: displayName,
            avatarURL: avatarURL,
            isPrimary: isPrimary,
            isPrimaryNotesAccount: isPrimaryNotesAccount,
            authMode: GoogleAccountAuthMode(rawValue: authMode) ?? .webSession
        )
    }

    public func apply(_ account: GoogleAccount) {
        email = account.email
        displayName = account.displayName
        avatarURL = account.avatarURL
        isPrimary = account.isPrimary
        isPrimaryNotesAccount = account.isPrimaryNotesAccount
        authMode = account.authMode.rawValue
    }
}

@Model
public final class ClipboardItemRecord {
    public var id: UUID = UUID()
    public var content: String = ""
    public var contentType: String = "text"
    public var sourceApplication: String = "Unknown"
    public var tagsCSV: String = ""
    public var isPinned: Bool = false
    public var capturedAt: Date = Date()

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
    public var id: UUID = UUID()
    public var title: String = ""
    public var markdown: String = ""
    public var folderRaw: String = NoteFolder.notes.rawValue
    public var updatedAt: Date = Date()
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
        NoteFolder.normalized(from: folderRaw)
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

@Model
public final class BillRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    public var amount: Double = 0
    public var categoryRaw: String = BillCategory.other.rawValue
    public var recurrenceRaw: String = BillRecurrence.monthly.rawValue
    public var customIntervalDays: Int?
    public var dueDayOfMonth: Int?
    public var nextDueDate: Date = Date()
    public var iconName: String = ""
    public var notes: String = ""
    public var isArchived: Bool = false
    public var createdAt: Date = Date()
    public var sortOrder: Int = 0

    public init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        categoryRaw: String,
        recurrenceRaw: String,
        customIntervalDays: Int? = nil,
        dueDayOfMonth: Int? = nil,
        nextDueDate: Date,
        iconName: String = "",
        notes: String = "",
        isArchived: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.categoryRaw = categoryRaw
        self.recurrenceRaw = recurrenceRaw
        self.customIntervalDays = customIntervalDays
        self.dueDayOfMonth = dueDayOfMonth
        self.nextDueDate = nextDueDate
        self.iconName = iconName
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    public var category: BillCategory {
        BillCategory(rawValue: categoryRaw) ?? .other
    }

    public var recurrence: BillRecurrence {
        BillRecurrence(rawValue: recurrenceRaw) ?? .monthly
    }

    public var bill: Bill {
        Bill(
            id: id,
            name: name,
            amount: amount,
            category: category,
            recurrence: recurrence,
            customIntervalDays: customIntervalDays,
            dueDayOfMonth: dueDayOfMonth,
            nextDueDate: nextDueDate,
            iconName: iconName,
            notes: notes,
            isArchived: isArchived,
            createdAt: createdAt,
            sortOrder: sortOrder
        )
    }

    public func apply(_ bill: Bill) {
        name = bill.name
        amount = bill.amount
        categoryRaw = bill.category.rawValue
        recurrenceRaw = bill.recurrence.rawValue
        customIntervalDays = bill.customIntervalDays
        dueDayOfMonth = bill.dueDayOfMonth
        nextDueDate = bill.nextDueDate
        iconName = bill.iconName
        notes = bill.notes
        isArchived = bill.isArchived
        sortOrder = bill.sortOrder
    }
}

@Model
public final class BillPaymentRecord {
    public var id: UUID = UUID()
    public var billID: UUID = UUID()
    public var amount: Double = 0
    public var paidAt: Date = Date()
    public var note: String = ""

    public init(
        id: UUID = UUID(),
        billID: UUID,
        amount: Double,
        paidAt: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.billID = billID
        self.amount = amount
        self.paidAt = paidAt
        self.note = note
    }

    public var payment: BillPayment {
        BillPayment(
            id: id,
            billID: billID,
            amount: amount,
            paidAt: paidAt,
            note: note
        )
    }
}

@Model
public final class SyncedSettingsRecord {
    public var id: UUID = NucleusSyncedConfiguration.singletonRecordID
    public var payloadData: Data = Data()
    public var updatedAt: Date = Date()

    public init(id: UUID, payloadData: Data, updatedAt: Date) {
        self.id = id
        self.payloadData = payloadData
        self.updatedAt = updatedAt
    }

    public init(configuration: NucleusSyncedConfiguration) throws {
        id = NucleusSyncedConfiguration.singletonRecordID
        payloadData = try JSONEncoder().encode(configuration)
        updatedAt = configuration.updatedAt
    }

    public var configuration: NucleusSyncedConfiguration {
        get throws {
            try JSONDecoder().decode(NucleusSyncedConfiguration.self, from: payloadData)
        }
    }

    public func apply(_ configuration: NucleusSyncedConfiguration) throws {
        payloadData = try JSONEncoder().encode(configuration)
        updatedAt = configuration.updatedAt
    }
}
