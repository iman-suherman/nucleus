import CoreData
import Foundation
import NucleusKit
import SwiftData

public enum NucleusDatabase {
    public static let cloudKitContainerIdentifier = "iCloud.net.suherman.nucleus"
    /// SwiftData stores synced records in this custom zone, not `_defaultZone`.
    public static let swiftDataCloudKitZoneName = "com.apple.coredata.cloudkit.zone"
    private static let developmentSchemaSeedDefaultsKey = "NucleusCloudKitDevelopmentSchemaSeeded"
    private static let notesCloudKitExportDefaultsKey = "NucleusCloudKitNotesExportedToCloudKit"
    private static let billsCloudKitExportDefaultsKey = "NucleusCloudKitBillsExportedToCloudKit"
    private static let dashboardCloudKitExportDefaultsKey = "NucleusCloudKitDashboardExportedToCloudKit"

    public struct SyncedCloudKitExportCounts: Sendable {
        public var notes: Int
        public var bills: Int
        public var dashboard: Int

        public var total: Int { notes + bills + dashboard }
    }

    /// Whether the active store configuration is syncing notes via CloudKit.
    public private(set) static var usesCloudKitSync = false
    /// Set when CloudKit container creation fails and the app falls back to local-only storage.
    public private(set) static var lastCloudKitSetupError: String?

    public static let syncedSchema = Schema([
        GoogleAccountRecord.self,
        NoteRecord.self,
        SyncedSettingsRecord.self,
        ClipboardItemRecord.self,
        BillRecord.self,
        BillPaymentRecord.self,
        DashboardAnalysisRecord.self,
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
        BillRecord.self,
        BillPaymentRecord.self,
        DashboardAnalysisRecord.self,
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

        if enableCloudKit && isCloudKitAvailable {
            do {
                let container = try makeCloudKitContainer()
                usesCloudKitSync = true
                lastCloudKitSetupError = nil
                NSLog(
                    "Nucleus: CloudKit notes sync enabled (container=%@, zone=%@)",
                    cloudKitContainerIdentifier,
                    swiftDataCloudKitZoneName
                )
                return container
            } catch {
                usesCloudKitSync = false
                lastCloudKitSetupError = error.localizedDescription
                NSLog(
                    "Nucleus: CloudKit notes sync unavailable, using local store only: %@",
                    error.localizedDescription
                )
                return try makeLocalContainer()
            }
        }

        usesCloudKitSync = false
        lastCloudKitSetupError = isCloudKitAvailable
            ? "CloudKit sync was disabled for this launch."
            : "Sign in to iCloud to sync notes across devices."
        NSLog(
            "Nucleus: CloudKit notes sync disabled: %@",
            lastCloudKitSetupError ?? "unknown"
        )
        return try makeLocalContainer()
    }

    /// Re-saves every note so SwiftData exports them to CloudKit (e.g. after enabling sync).
    @discardableResult
    public static func exportNotesToCloudKit(context: ModelContext, force: Bool = false) throws -> Int {
        guard usesCloudKitSync else { return 0 }
        if !force, UserDefaults.standard.bool(forKey: notesCloudKitExportDefaultsKey) {
            return 0
        }

        let count = try NoteRepository.touchAllForCloudKitExport(context: context)
        if count > 0 || force {
            UserDefaults.standard.set(true, forKey: notesCloudKitExportDefaultsKey)
            NSLog("Nucleus: Queued %ld note(s) for CloudKit export.", count)
        }
        return count
    }

    /// Re-saves every bill and payment so SwiftData exports them to CloudKit.
    @discardableResult
    public static func exportBillsToCloudKit(context: ModelContext, force: Bool = false) throws -> Int {
        guard usesCloudKitSync else { return 0 }
        if !force, UserDefaults.standard.bool(forKey: billsCloudKitExportDefaultsKey) {
            return 0
        }

        let count = try BillRepository.touchAllForCloudKitExport(context: context)
        if count > 0 || force {
            UserDefaults.standard.set(true, forKey: billsCloudKitExportDefaultsKey)
            NSLog("Nucleus: Queued %ld bill/payment record(s) for CloudKit export.", count)
        }
        return count
    }

    private static var isCloudKitAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private static func makeCloudKitContainer() throws -> ModelContainer {
        let syncedConfiguration = ModelConfiguration(
            "Synced",
            schema: syncedSchema,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
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
            BillRecord.self,
            BillPaymentRecord.self,
            DashboardAnalysisRecord.self,
            CalendarEventRecord.self,
            ActivityNotificationRecord.self,
            MailMessageRecord.self,
            configurations: syncedConfiguration,
            localConfiguration
        )
    }

    private static func makeLocalContainer() throws -> ModelContainer {
        let syncedConfiguration = ModelConfiguration(
            "Synced",
            schema: syncedSchema,
            cloudKitDatabase: .none
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
            BillRecord.self,
            BillPaymentRecord.self,
            DashboardAnalysisRecord.self,
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

    /// Removes SwiftData store files from Application Support (Synced, Local, and legacy paths).
    public static func removeAllLocalStoreFiles() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let fileManager = FileManager.default

        for baseName in ["Synced", "Local", "Nucleus", "default"] {
            for suffix in ["", "-shm", "-wal"] {
                let url = appSupport.appendingPathComponent("\(baseName).store\(suffix)")
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
        }

        for auxiliary in ["Synced_ckAssets", ".Synced_SUPPORT"] {
            let url = appSupport.appendingPathComponent(auxiliary)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        let legacyDirectory = appSupport.appendingPathComponent("Nucleus", isDirectory: true)
        if fileManager.fileExists(atPath: legacyDirectory.path) {
            try fileManager.removeItem(at: legacyDirectory)
        }
    }

    /// Re-saves dashboard analysis so SwiftData exports it to CloudKit.
    @discardableResult
    public static func exportDashboardToCloudKit(context: ModelContext, force: Bool = false) throws -> Int {
        guard usesCloudKitSync else { return 0 }
        if !force, UserDefaults.standard.bool(forKey: dashboardCloudKitExportDefaultsKey) {
            return 0
        }

        let count = try DashboardAnalysisRepository.touchForCloudKitExport(context: context)
        if count > 0 || force {
            UserDefaults.standard.set(true, forKey: dashboardCloudKitExportDefaultsKey)
            NSLog("Nucleus: Queued dashboard analysis for CloudKit export.")
        }
        return count
    }

    @discardableResult
    public static func exportSyncedDataToCloudKit(context: ModelContext, force: Bool = false) throws -> SyncedCloudKitExportCounts {
        SyncedCloudKitExportCounts(
            notes: try exportNotesToCloudKit(context: context, force: force),
            bills: try exportBillsToCloudKit(context: context, force: force),
            dashboard: try exportDashboardToCloudKit(context: context, force: force)
        )
    }

    /// Clears CloudKit export flags so a fresh store re-exports to iCloud.
    public static func resetCloudKitUserDefaults() {
        UserDefaults.standard.removeObject(forKey: notesCloudKitExportDefaultsKey)
        UserDefaults.standard.removeObject(forKey: billsCloudKitExportDefaultsKey)
        UserDefaults.standard.removeObject(forKey: dashboardCloudKitExportDefaultsKey)
        UserDefaults.standard.removeObject(forKey: developmentSchemaSeedDefaultsKey)
    }

    /// Uploads SwiftData model metadata to the CloudKit **Development** schema.
    /// Invoke with `NUCLEUS_SEED_CLOUDKIT_SCHEMA=1` during local setup only.
    public static func seedDevelopmentCloudKitSchemaIfNeeded(force: Bool = false) {
        let shouldSeed = force || ProcessInfo.processInfo.environment["NUCLEUS_SEED_CLOUDKIT_SCHEMA"] == "1"
        guard shouldSeed else { return }

        if !force, UserDefaults.standard.bool(forKey: developmentSchemaSeedDefaultsKey) {
            return
        }

        do {
            try seedDevelopmentCloudKitSchema()
            UserDefaults.standard.set(true, forKey: developmentSchemaSeedDefaultsKey)
            NSLog("Nucleus: CloudKit Development schema initialized.")
        } catch {
            let nsError = error as NSError
            NSLog(
                "Nucleus: CloudKit Development schema init failed: %@ (%@ %ld) userInfo=%@",
                nsError.localizedDescription,
                nsError.domain,
                nsError.code,
                String(describing: nsError.userInfo)
            )
        }
    }

    private static func seedDevelopmentCloudKitSchema() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nucleus-cloudkit-schema-seed.store")
        try? FileManager.default.removeItem(at: seedURL)

        let syncedModels: [any PersistentModel.Type] = [
            GoogleAccountRecord.self,
            NoteRecord.self,
            SyncedSettingsRecord.self,
            ClipboardItemRecord.self,
            BillRecord.self,
            BillPaymentRecord.self,
            DashboardAnalysisRecord.self,
        ]
        guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(for: syncedModels) else {
            throw NSError(domain: "NucleusDatabase", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build Core Data model from SwiftData types.",
            ])
        }

        let description = NSPersistentStoreDescription(url: seedURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(
            name: "Synced",
            managedObjectModel: managedObjectModel
        )
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        do {
            try container.initializeCloudKitSchema()
        } catch {
            let nsError = error as NSError
            throw NSError(
                domain: nsError.domain,
                code: nsError.code,
                userInfo: nsError.userInfo.merging([
                    NSLocalizedDescriptionKey: nsError.localizedDescription,
                    "NSDetailedErrors": nsError.userInfo,
                ]) { _, new in new }
            )
        }

        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: seedURL)
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
    public static let retentionDays = 7

    public static func retentionCutoff(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: now)) ?? now
    }

    public static func fetchRecent(
        context: ModelContext,
        limit: Int? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [ClipboardEntry] {
        let cutoff = retentionCutoff(from: now, calendar: calendar)
        let descriptor = FetchDescriptor<ClipboardItemRecord>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        var entries = try context.fetch(descriptor)
            .filter { $0.capturedAt >= cutoff || $0.isPinned }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.capturedAt > rhs.capturedAt
            }
            .map(\.entry)

        if let limit, limit > 0, entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        return entries
    }

    public static func search(query: String, context: ModelContext, now: Date = Date(), calendar: Calendar = .current) throws -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try fetchRecent(context: context, now: now, calendar: calendar)
        }

        let cutoff = retentionCutoff(from: now, calendar: calendar)
        let descriptor = FetchDescriptor<ClipboardItemRecord>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let lowered = trimmed.lowercased()
        return try context.fetch(descriptor)
            .filter {
                ($0.capturedAt >= cutoff || $0.isPinned)
                    && (
                        $0.content.lowercased().contains(lowered)
                            || $0.sourceApplication.lowercased().contains(lowered)
                            || $0.tags.contains { $0.lowercased().contains(lowered) }
                    )
            }
            .map(\.entry)
    }

    public static func insert(
        _ entry: ClipboardEntry,
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        context.insert(ClipboardItemRecord(
            id: entry.id,
            content: entry.content,
            contentType: entry.contentType,
            sourceApplication: entry.sourceApplication,
            tagsCSV: entry.tags.joined(separator: ","),
            isPinned: entry.isPinned,
            capturedAt: entry.capturedAt
        ))
        try prune(context: context, now: now, calendar: calendar)
        try context.save()
    }

    /// Removes clipboard captures older than `retentionDays`. Pinned items are kept.
    public static func prune(
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let cutoff = retentionCutoff(from: now, calendar: calendar)
        let descriptor = FetchDescriptor<ClipboardItemRecord>(
            predicate: #Predicate { $0.capturedAt < cutoff }
        )
        let expired = try context.fetch(descriptor)
        guard !expired.isEmpty else { return }

        for record in expired where !record.isPinned {
            context.delete(record)
        }
        try context.save()
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
        let records = try context.fetch(descriptor)
        var didMigrate = false

        for record in records {
            let normalized = NoteFolder.normalized(from: record.folderRaw)
            if record.folderRaw != normalized.rawValue {
                record.folderRaw = normalized.rawValue
                didMigrate = true
            }
        }

        if didMigrate {
            try context.save()
        }

        return records.map(\.document)
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

    /// Bumps `updatedAt` on every note and saves once to trigger a CloudKit export.
    public static func touchAllForCloudKitExport(context: ModelContext) throws -> Int {
        let records = try context.fetch(FetchDescriptor<NoteRecord>())
        guard !records.isEmpty else { return 0 }

        let exportStamp = Date()
        for record in records {
            record.updatedAt = exportStamp
            record.markdown += "\u{200B}"
        }
        try context.save()
        for record in records {
            if record.markdown.hasSuffix("\u{200B}") {
                record.markdown.removeLast()
            }
        }
        try context.save()
        return records.count
    }

    public static func delete(id: UUID, context: ModelContext) throws {
        var descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }

    public static func deleteAll(context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<NoteRecord>())
        guard !records.isEmpty else { return }
        for record in records {
            context.delete(record)
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

    public static func fetchRecent(context: ModelContext, limit: Int = 200) throws -> [MailMessageSummary] {
        let descriptor = FetchDescriptor<MailMessageRecord>(
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)
        if limit <= 0 {
            return records.map(\.summary)
        }
        return records.prefix(limit).map(\.summary)
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

public enum BillRepository {
    public static func fetchAll(context: ModelContext, includeArchived: Bool = false) throws -> [Bill] {
        let descriptor = FetchDescriptor<BillRecord>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.name),
            ]
        )
        let records = try context.fetch(descriptor)
        if includeArchived {
            return records.map(\.bill)
        }
        return records.filter { !$0.isArchived }.map(\.bill)
    }

    public static func upsert(_ bill: Bill, context: ModelContext) throws {
        let targetID = bill.id
        var descriptor = FetchDescriptor<BillRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.apply(bill)
        } else {
            let nextSortOrder = try nextBillSortOrder(context: context)
            context.insert(BillRecord(
                id: bill.id,
                name: bill.name,
                amount: bill.amount,
                categoryRaw: bill.category.rawValue,
                recurrenceRaw: bill.recurrence.rawValue,
                customIntervalDays: bill.customIntervalDays,
                dueDayOfMonth: bill.dueDayOfMonth,
                nextDueDate: bill.nextDueDate,
                iconName: bill.iconName,
                notes: bill.notes,
                isArchived: bill.isArchived,
                createdAt: bill.createdAt,
                sortOrder: bill.sortOrder == 0 ? nextSortOrder : bill.sortOrder
            ))
        }
        try context.save()
    }

    public static func delete(id: UUID, context: ModelContext) throws {
        let targetID = id
        var billDescriptor = FetchDescriptor<BillRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        billDescriptor.fetchLimit = 1
        if let existing = try context.fetch(billDescriptor).first {
            context.delete(existing)
        }

        let paymentDescriptor = FetchDescriptor<BillPaymentRecord>(
            predicate: #Predicate { $0.billID == targetID }
        )
        for payment in try context.fetch(paymentDescriptor) {
            context.delete(payment)
        }
        try context.save()
    }

    public static func fetchPayments(context: ModelContext, billID: UUID? = nil) throws -> [BillPayment] {
        if let billID {
            let targetID = billID
            let descriptor = FetchDescriptor<BillPaymentRecord>(
                predicate: #Predicate { $0.billID == targetID },
                sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
            )
            return try context.fetch(descriptor).map(\.payment)
        }

        let descriptor = FetchDescriptor<BillPaymentRecord>(
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.payment)
    }

    public static func insertPayment(_ payment: BillPayment, context: ModelContext) throws {
        context.insert(BillPaymentRecord(
            id: payment.id,
            billID: payment.billID,
            amount: payment.amount,
            paidAt: payment.paidAt,
            note: payment.note
        ))
        try context.save()
    }

    private static func nextBillSortOrder(context: ModelContext) throws -> Int {
        let records = try context.fetch(FetchDescriptor<BillRecord>())
        return (records.map(\.sortOrder).max() ?? -1) + 1
    }

    public static func importData(
        bills: [Bill],
        payments: [BillPayment],
        context: ModelContext,
        replaceExisting: Bool = false
    ) throws -> BillCSVImportResult {
        if replaceExisting {
            for record in try context.fetch(FetchDescriptor<BillRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<BillPaymentRecord>()) {
                context.delete(record)
            }
        }

        let existingRecords = try context.fetch(FetchDescriptor<BillRecord>())
        var billIDMap: [UUID: UUID] = [:]
        var importedBills = 0

        for bill in bills {
            if let match = existingRecords.first(where: { $0.name.caseInsensitiveCompare(bill.name) == .orderedSame }) {
                billIDMap[bill.id] = match.id
                var updated = bill
                updated = Bill(
                    id: match.id,
                    name: bill.name,
                    amount: bill.amount,
                    category: bill.category,
                    recurrence: bill.recurrence,
                    customIntervalDays: bill.customIntervalDays,
                    dueDayOfMonth: bill.dueDayOfMonth,
                    nextDueDate: bill.nextDueDate,
                    iconName: bill.iconName,
                    notes: bill.notes,
                    isArchived: bill.isArchived,
                    createdAt: match.createdAt,
                    sortOrder: bill.sortOrder == 0 ? match.sortOrder : bill.sortOrder
                )
                match.apply(updated)
            } else {
                billIDMap[bill.id] = bill.id
                importedBills += 1
                let nextSortOrder = try nextBillSortOrder(context: context)
                context.insert(BillRecord(
                    id: bill.id,
                    name: bill.name,
                    amount: bill.amount,
                    categoryRaw: bill.category.rawValue,
                    recurrenceRaw: bill.recurrence.rawValue,
                    customIntervalDays: bill.customIntervalDays,
                    dueDayOfMonth: bill.dueDayOfMonth,
                    nextDueDate: bill.nextDueDate,
                    iconName: bill.iconName,
                    notes: bill.notes,
                    isArchived: bill.isArchived,
                    createdAt: bill.createdAt,
                    sortOrder: bill.sortOrder == 0 ? nextSortOrder : bill.sortOrder
                ))
            }
        }

        let existingPaymentIDs = Set(try context.fetch(FetchDescriptor<BillPaymentRecord>()).map(\.id))
        var importedPayments = 0
        for payment in payments {
            guard !existingPaymentIDs.contains(payment.id) else { continue }
            let resolvedBillID = billIDMap[payment.billID] ?? payment.billID
            context.insert(BillPaymentRecord(
                id: payment.id,
                billID: resolvedBillID,
                amount: payment.amount,
                paidAt: payment.paidAt,
                note: payment.note
            ))
            importedPayments += 1
        }

        try context.save()
        return BillCSVImportResult(billsImported: importedBills, paymentsImported: importedPayments)
    }

    @discardableResult
    public static func touchAllForCloudKitExport(context: ModelContext) throws -> Int {
        let billRecords = try context.fetch(FetchDescriptor<BillRecord>())
        let paymentRecords = try context.fetch(FetchDescriptor<BillPaymentRecord>())
        guard !billRecords.isEmpty || !paymentRecords.isEmpty else { return 0 }

        for record in billRecords {
            record.notes += "\u{200B}"
        }
        for record in paymentRecords {
            record.note += "\u{200B}"
        }
        try context.save()

        for record in billRecords where record.notes.hasSuffix("\u{200B}") {
            record.notes.removeLast()
        }
        for record in paymentRecords where record.note.hasSuffix("\u{200B}") {
            record.note.removeLast()
        }
        try context.save()
        return billRecords.count + paymentRecords.count
    }
}

public enum DashboardAnalysisRepository {
    public static func fetch(context: ModelContext) throws -> StoredDashboardAnalysis? {
        let singletonID = DashboardAnalysisRecord.singletonRecordID
        var descriptor = FetchDescriptor<DashboardAnalysisRecord>(
            predicate: #Predicate { $0.id == singletonID }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return nil }
        return try record.storedAnalysis
    }

    public static func upsert(_ stored: StoredDashboardAnalysis, context: ModelContext) throws {
        let singletonID = DashboardAnalysisRecord.singletonRecordID
        var descriptor = FetchDescriptor<DashboardAnalysisRecord>(
            predicate: #Predicate { $0.id == singletonID }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            try existing.apply(stored)
        } else {
            context.insert(try DashboardAnalysisRecord(stored: stored))
        }
        try context.save()
    }

    @discardableResult
    public static func touchForCloudKitExport(context: ModelContext) throws -> Int {
        let singletonID = DashboardAnalysisRecord.singletonRecordID
        var descriptor = FetchDescriptor<DashboardAnalysisRecord>(
            predicate: #Predicate { $0.id == singletonID }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return 0 }

        record.updatedAt = Date()
        record.payloadData.append(0)
        try context.save()
        record.payloadData.removeLast()
        try context.save()
        return 1
    }
}
