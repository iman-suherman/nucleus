import Foundation
import NucleusKit
import SwiftData

public enum NucleusDatabase {
    public static let syncedSchema = Schema([
        GoogleAccountRecord.self,
        NoteRecord.self,
        SyncedSettingsRecord.self,
        ClipboardItemRecord.self,
    ])

    public static let localSchema = Schema([
        CalendarEventRecord.self,
        ActivityNotificationRecord.self,
        MailMessageRecord.self,
    ])

    public static let schema = Schema([
        GoogleAccountRecord.self,
        NoteRecord.self,
        SyncedSettingsRecord.self,
        ClipboardItemRecord.self,
        CalendarEventRecord.self,
        ActivityNotificationRecord.self,
        MailMessageRecord.self,
    ])

    public static func makeContainer(
        inMemory: Bool = false,
        enableCloudKit: Bool = true
    ) throws -> ModelContainer {
        if inMemory {
            let configuration = ModelConfiguration(
                "Nucleus",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let syncedConfiguration = ModelConfiguration(
            "Synced",
            schema: syncedSchema,
            cloudKitDatabase: enableCloudKit ? .automatic : .none
        )

        let localConfiguration = ModelConfiguration(
            "Local",
            schema: localSchema,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: GoogleAccountRecord.self,
            NoteRecord.self,
            SyncedSettingsRecord.self,
            ClipboardItemRecord.self,
            CalendarEventRecord.self,
            ActivityNotificationRecord.self,
            MailMessageRecord.self,
            configurations: syncedConfiguration,
            localConfiguration
        )
    }

    public static func defaultStoreURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Nucleus/nucleus.store", isDirectory: false)
    }
}

public enum AccountRepository {
    public static func fetchAll(context: ModelContext) throws -> [GoogleAccount] {
        let descriptor = FetchDescriptor<GoogleAccountRecord>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.email),
            ]
        )
        return try context.fetch(descriptor).map(\.model)
    }

    public static func upsert(_ account: GoogleAccount, context: ModelContext) throws {
        let targetID = account.id
        var descriptor = FetchDescriptor<GoogleAccountRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.apply(account)
        } else {
            let nextSortOrder = try nextAccountSortOrder(context: context)
            context.insert(GoogleAccountRecord(
                id: account.id,
                email: account.email,
                displayName: account.displayName,
                avatarURL: account.avatarURL,
                isPrimary: account.isPrimary,
                isPrimaryNotesAccount: account.isPrimaryNotesAccount,
                authMode: account.authMode.rawValue,
                sortOrder: nextSortOrder
            ))
        }
        try context.save()
    }

    public static func delete(id: UUID, context: ModelContext) throws {
        let targetID = id
        var descriptor = FetchDescriptor<GoogleAccountRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }

    public static func setPrimary(id: UUID, context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<GoogleAccountRecord>())
        for record in all {
            record.isPrimary = record.id == id
        }
        try context.save()
    }

    public static func setPrimaryNotesAccount(id: UUID, context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<GoogleAccountRecord>())
        for record in all {
            record.isPrimaryNotesAccount = record.id == id
        }
        try context.save()
    }

    private static func nextAccountSortOrder(context: ModelContext) throws -> Int {
        let records = try context.fetch(FetchDescriptor<GoogleAccountRecord>())
        return (records.map(\.sortOrder).max() ?? -1) + 1
    }
}

public enum SyncedSettingsRepository {
    public static func fetch(context: ModelContext) throws -> NucleusSyncedConfiguration? {
        let singletonID = NucleusSyncedConfiguration.singletonRecordID
        var descriptor = FetchDescriptor<SyncedSettingsRecord>(
            predicate: #Predicate { $0.id == singletonID }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return nil }
        return try record.configuration
    }

    public static func upsert(_ configuration: NucleusSyncedConfiguration, context: ModelContext) throws {
        let singletonID = NucleusSyncedConfiguration.singletonRecordID
        var descriptor = FetchDescriptor<SyncedSettingsRecord>(
            predicate: #Predicate { $0.id == singletonID }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            try existing.apply(configuration)
        } else {
            context.insert(try SyncedSettingsRecord(configuration: configuration))
        }
        try context.save()
    }
}

public enum ClipboardRepository {
    public static func fetchRecent(context: ModelContext, limit: Int = 200) throws -> [ClipboardEntry] {
        var descriptor = FetchDescriptor<ClipboardItemRecord>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.capturedAt > rhs.capturedAt
            }
            .map(\.entry)
    }

    public static func search(query: String, context: ModelContext) throws -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try fetchRecent(context: context)
        }

        let descriptor = FetchDescriptor<ClipboardItemRecord>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let lowered = trimmed.lowercased()
        return try context.fetch(descriptor)
            .filter {
                $0.content.lowercased().contains(lowered)
                    || $0.sourceApplication.lowercased().contains(lowered)
                    || $0.tags.contains { $0.lowercased().contains(lowered) }
            }
            .map(\.entry)
    }

    public static func insert(_ entry: ClipboardEntry, context: ModelContext, maxItems: Int = 200) throws {
        context.insert(ClipboardItemRecord(
            id: entry.id,
            content: entry.content,
            contentType: entry.contentType,
            sourceApplication: entry.sourceApplication,
            tagsCSV: entry.tags.joined(separator: ","),
            isPinned: entry.isPinned,
            capturedAt: entry.capturedAt
        ))
        try prune(context: context, maxItems: maxItems)
        try context.save()
    }

    public static func prune(context: ModelContext, maxItems: Int = 200) throws {
        let descriptor = FetchDescriptor<ClipboardItemRecord>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)
        guard records.count > maxItems else { return }

        let overflow = records.dropFirst(maxItems)
        for record in overflow where !record.isPinned {
            context.delete(record)
        }
    }

    public static func setPinned(id: UUID, pinned: Bool, context: ModelContext) throws {
        let targetID = id
        var descriptor = FetchDescriptor<ClipboardItemRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.isPinned = pinned
            try context.save()
        }
    }
}

public enum ActivityRepository {
    public static func append(_ item: ActivityItem, context: ModelContext) throws {
        context.insert(ActivityNotificationRecord(
            id: item.id,
            title: item.title,
            detail: item.detail,
            sourceRaw: item.source.rawValue,
            timestamp: item.timestamp,
            accountEmail: item.accountEmail
        ))
        try context.save()
    }

    public static func fetchRecent(context: ModelContext, limit: Int = 100) throws -> [ActivityItem] {
        var descriptor = FetchDescriptor<ActivityNotificationRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(\.item)
    }
}

public enum NoteRepository {
    public static func fetchAll(context: ModelContext) throws -> [NoteDocument] {
        let descriptor = FetchDescriptor<NoteRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.document)
    }

    public static func upsert(_ note: NoteDocument, context: ModelContext) throws {
        let targetID = note.id
        var descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.title = note.title
            existing.markdown = note.markdown
            existing.folderRaw = note.folder.rawValue
            existing.updatedAt = note.updatedAt
            existing.driveFileID = note.driveFileID
        } else {
            context.insert(NoteRecord(
                id: note.id,
                title: note.title,
                markdown: note.markdown,
                folderRaw: note.folder.rawValue,
                updatedAt: note.updatedAt,
                driveFileID: note.driveFileID
            ))
        }
        try context.save()
    }
}

public enum CalendarRepository {
    public static func replaceEvents(_ events: [CalendarEventSummary], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<CalendarEventRecord>())
        for record in existing {
            context.delete(record)
        }
        for event in events {
            context.insert(CalendarEventRecord(
                id: event.id,
                accountID: event.accountID,
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                attendeesCSV: event.attendees.joined(separator: ";"),
                meetingLink: event.meetingLink,
                accountEmail: event.accountEmail
            ))
        }
        try context.save()
    }

    public static func fetchUpcoming(context: ModelContext, from date: Date = Date()) throws -> [CalendarEventSummary] {
        let start = date
        let descriptor = FetchDescriptor<CalendarEventRecord>(
            predicate: #Predicate { $0.endDate >= start },
            sortBy: [SortDescriptor(\.startDate)]
        )
        return try context.fetch(descriptor).map(\.summary)
    }
}

public enum MailRepository {
    public static func unreadCount(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<MailMessageRecord>(
            predicate: #Predicate { $0.isUnread == true }
        )
        return try context.fetchCount(descriptor)
    }

    public static func unreadCount(for accountID: UUID, context: ModelContext) throws -> Int {
        let targetID = accountID
        let descriptor = FetchDescriptor<MailMessageRecord>(
            predicate: #Predicate { $0.accountID == targetID && $0.isUnread == true }
        )
        return try context.fetchCount(descriptor)
    }

    public static func replaceMessages(_ messages: [MailMessageSummary], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<MailMessageRecord>())
        for record in existing {
            context.delete(record)
        }
        for message in messages {
            context.insert(MailMessageRecord(
                id: message.id,
                accountID: message.accountID,
                threadID: message.threadID,
                fromName: message.fromName,
                fromEmail: message.fromEmail,
                subject: message.subject,
                snippet: message.snippet,
                receivedAt: message.receivedAt,
                isUnread: message.isUnread
            ))
        }
        try context.save()
    }
}
