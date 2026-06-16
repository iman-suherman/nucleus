import CloudKit
import Combine
import CoreData
import DatabaseKit
import Foundation

public enum NotesExportOutcome: Equatable {
    case idle
    case exporting
    case succeeded(noteCount: Int)
    case failed(String)
    case timedOut(noteCount: Int)
}

public enum BillsExportOutcome: Equatable {
    case idle
    case exporting
    case succeeded(recordCount: Int)
    case failed(String)
    case timedOut(recordCount: Int)
}

private enum ActiveCloudKitUpload {
    case notes
    case bills
    case synced
}

public extension Notification.Name {
    static let nucleusCloudKitDataDidChange = Notification.Name("NucleusCloudKitDataDidChange")
}

@MainActor
public final class CloudKitSyncService: ObservableObject {
    public static let shared = CloudKitSyncService()

    public enum SyncStatus: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case unavailable
        case error(String)

        public var isAvailable: Bool {
            self == .available
        }

        public var label: String {
            switch self {
            case .checking:
                return "Checking iCloud…"
            case .available:
                return "Syncing via iCloud"
            case .noAccount:
                return "Sign in to iCloud to sync"
            case .restricted:
                return "iCloud access restricted"
            case .temporarilyUnavailable:
                return "iCloud temporarily unavailable"
            case .unavailable:
                return "iCloud sync is not configured for this build"
            case .error(let message):
                return message
            }
        }
    }

    @Published public private(set) var status: SyncStatus = .checking
    @Published public private(set) var lastRemoteChangeAt: Date?
    @Published public private(set) var iCloudAccountProfile = ICloudAccountProfile()
    @Published public private(set) var isNotesSyncInProgress = false
    @Published public private(set) var notesExportOutcome: NotesExportOutcome = .idle
    @Published public private(set) var isBillsSyncInProgress = false
    @Published public private(set) var billsExportOutcome: BillsExportOutcome = .idle
    @Published public private(set) var lastCloudKitExportError: String?
    @Published public private(set) var syncLogStore = CloudKitSyncLogStore.shared

    private let ubiquityContainerIdentifier: String?
    private var remoteChangeObserver: NSObjectProtocol?
    private var cloudKitExportObserver: NSObjectProtocol?
    private var notesSyncClearTask: Task<Void, Never>?
    private var billsSyncClearTask: Task<Void, Never>?
    private var remoteChangeDebounceTask: Task<Void, Never>?
    private var activeUpload: ActiveCloudKitUpload?

    public init(ubiquityContainerIdentifier: String? = "iCloud.net.suherman.nucleus") {
        self.ubiquityContainerIdentifier = ubiquityContainerIdentifier
    }

    public func start() {
        observeRemoteChanges()
        observeCloudKitExportEvents()
        log("CloudKit sync service started")
        Task { await refreshAccountStatus() }
    }

    public func log(_ message: String, level: CloudKitSyncLogEntry.Level = .info) {
        syncLogStore.log(message, level: level)
    }

    public func clearSyncLog() {
        syncLogStore.clear()
    }

    /// Registers for the next CloudKit export, runs `performExport`, then waits for completion.
    public func queueNotesExportAndWait(
        performExport: @escaping @MainActor () throws -> Int,
        timeoutSeconds: TimeInterval = 30
    ) async -> String {
        await queueExportAndWait(
            target: .notes,
            performExport: performExport,
            timeoutSeconds: timeoutSeconds
        )
    }

    public func queueBillsExportAndWait(
        performExport: @escaping @MainActor () throws -> Int,
        timeoutSeconds: TimeInterval = 30
    ) async -> String {
        await queueExportAndWait(
            target: .bills,
            performExport: performExport,
            timeoutSeconds: timeoutSeconds
        )
    }

    public func queueSyncedExportAndWait(
        performExport: @escaping @MainActor () throws -> NucleusDatabase.SyncedCloudKitExportCounts,
        timeoutSeconds: TimeInterval = 45
    ) async -> String {
        log("Sync to iCloud requested")
        activeUpload = .synced
        setExporting(true, for: .synced)

        async let exportWait = waitForCloudKitExport(timeoutSeconds: timeoutSeconds)

        await Task.yield()
        await Task.yield()

        let exportedCounts: NucleusDatabase.SyncedCloudKitExportCounts
        do {
            log("Queuing notes, bills, and dashboard for CloudKit export…")
            exportedCounts = try performExport()
            log(
                "Marked \(exportedCounts.notes) note(s), \(exportedCounts.bills) bill/payment record(s), and \(exportedCounts.dashboard) dashboard record(s) for export"
            )
        } catch {
            setExporting(false, for: .synced)
            setFailed(error.localizedDescription, for: .synced)
            log("Failed to queue iCloud sync: \(error.localizedDescription)", level: .error)
            activeUpload = nil
            return error.localizedDescription
        }

        guard exportedCounts.total > 0 else {
            setExporting(false, for: .synced)
            setIdle(for: .synced)
            log("No synced data needed re-export — already queued", level: .warning)
            activeUpload = nil
            return "Synced data is already queued for iCloud."
        }

        log("Waiting for CloudKit export (timeout \(Int(timeoutSeconds))s)…")
        let exportEvent = await exportWait
        setExporting(false, for: .synced)
        activeUpload = nil

        switch exportEvent {
        case .completed:
            notesExportOutcome = .succeeded(noteCount: exportedCounts.notes)
            billsExportOutcome = .succeeded(recordCount: exportedCounts.bills)
            let message =
                "Synced \(exportedCounts.notes) note(s), \(exportedCounts.bills) bill/payment record(s), and dashboard analysis to iCloud."
            log(message, level: .success)
            return message
        case .failed(let error):
            let message = Self.exportFailureMessage(error)
            notesExportOutcome = .failed(message)
            billsExportOutcome = .failed(message)
            log(message, level: .error)
            return message
        case .timedOut:
            notesExportOutcome = .timedOut(noteCount: exportedCounts.notes)
            billsExportOutcome = .timedOut(recordCount: exportedCounts.bills)
            let message =
                "Sync started for \(exportedCounts.total) record(s), but CloudKit has not finished within \(Int(timeoutSeconds)) seconds. Leave Nucleus open and try again."
            log(message, level: .warning)
            return message
        case .cancelled:
            notesExportOutcome = .idle
            billsExportOutcome = .idle
            return "Sync cancelled."
        }
    }

    private func queueExportAndWait(
        target: ActiveCloudKitUpload,
        performExport: @escaping @MainActor () throws -> Int,
        timeoutSeconds: TimeInterval
    ) async -> String {
        let requestLabel = target == .notes ? "Notes" : "Bills"
        let entitySingular = target == .notes ? "note" : "bill/payment record"
        let entityPlural = target == .notes ? "notes" : "bill/payment records"

        log("Upload \(requestLabel) to iCloud requested")
        activeUpload = target
        setExporting(true, for: target)

        async let exportWait = waitForCloudKitExport(timeoutSeconds: timeoutSeconds)

        // Let the export listener register before we save and trigger CloudKit.
        await Task.yield()
        await Task.yield()

        let exportedCount: Int
        do {
            log("Queuing local \(entityPlural) for CloudKit export…")
            exportedCount = try performExport()
            log("Marked \(exportedCount) \(entitySingular) for export")
        } catch {
            setExporting(false, for: target)
            setFailed(error.localizedDescription, for: target)
            log("Failed to queue \(entityPlural): \(error.localizedDescription)", level: .error)
            activeUpload = nil
            return error.localizedDescription
        }

        guard exportedCount > 0 else {
            setExporting(false, for: target)
            setIdle(for: target)
            log("No \(entityPlural) needed re-export — already queued", level: .warning)
            activeUpload = nil
            return "\(requestLabel) are already queued for iCloud sync."
        }

        log("Waiting for CloudKit export (timeout \(Int(timeoutSeconds))s)…")

        let exportEvent = await exportWait
        setExporting(false, for: target)
        activeUpload = nil

        switch target {
        case .notes:
            return await finishNotesExport(
                exportedCount: exportedCount,
                exportEvent: exportEvent,
                timeoutSeconds: timeoutSeconds
            )
        case .bills:
            return await finishBillsExport(
                exportedCount: exportedCount,
                exportEvent: exportEvent,
                timeoutSeconds: timeoutSeconds
            )
        case .synced:
            return "Unexpected synced export path."
        }
    }

    private func finishNotesExport(
        exportedCount: Int,
        exportEvent: ExportWaitResult,
        timeoutSeconds: TimeInterval
    ) async -> String {
        let noteWord = exportedCount == 1 ? "note" : "notes"
        let cloudKitNoteCount = await countNotesInCloudKit()

        switch exportEvent {
        case .completed:
            notesExportOutcome = .succeeded(noteCount: exportedCount)
            let message = "Uploaded \(exportedCount) \(noteWord) to iCloud."
            log(message, level: .success)
            if let cloudKitNoteCount {
                log("CloudKit has \(cloudKitNoteCount) note record(s) in iCloud", level: .success)
            }
            return message
        case .failed(let error):
            let message = Self.exportFailureMessage(error)
            notesExportOutcome = .failed(message)
            log(message, level: .error)
            return message
        case .timedOut:
            notesExportOutcome = .timedOut(noteCount: exportedCount)
            if let cloudKitNoteCount {
                log("CloudKit has \(cloudKitNoteCount) note record(s) in iCloud", level: .info)
                if cloudKitNoteCount >= exportedCount {
                    let message =
                        "No export event fired, but iCloud already has \(cloudKitNoteCount) note record(s). "
                        + "Your notes may already be uploaded — open Notes on your other Mac and refresh."
                    log(message, level: .success)
                    notesExportOutcome = .succeeded(noteCount: exportedCount)
                    return message
                }
            }
            return await messageForNotesExportTimeout(
                localNoteCount: exportedCount,
                timeoutSeconds: timeoutSeconds
            )
        case .cancelled:
            notesExportOutcome = .idle
            return "Upload cancelled."
        }
    }

    private func finishBillsExport(
        exportedCount: Int,
        exportEvent: ExportWaitResult,
        timeoutSeconds: TimeInterval
    ) async -> String {
        let recordWord = exportedCount == 1 ? "record" : "records"
        let cloudKitBillCounts = await countBillsInCloudKit()

        switch exportEvent {
        case .completed:
            billsExportOutcome = .succeeded(recordCount: exportedCount)
            let message = "Uploaded \(exportedCount) bill/payment \(recordWord) to iCloud."
            log(message, level: .success)
            if let cloudKitBillCounts {
                log(
                    "CloudKit has \(cloudKitBillCounts.bills) bill record(s) and \(cloudKitBillCounts.payments) payment record(s) in iCloud",
                    level: .success
                )
            }
            return message
        case .failed(let error):
            let message = Self.exportFailureMessage(error)
            billsExportOutcome = .failed(message)
            log(message, level: .error)
            return message
        case .timedOut:
            billsExportOutcome = .timedOut(recordCount: exportedCount)
            if let cloudKitBillCounts {
                log(
                    "CloudKit has \(cloudKitBillCounts.bills) bill record(s) and \(cloudKitBillCounts.payments) payment record(s) in iCloud",
                    level: .info
                )
                let remoteTotal = cloudKitBillCounts.bills + cloudKitBillCounts.payments
                if remoteTotal >= exportedCount {
                    let message =
                        "No export event fired, but iCloud already has \(remoteTotal) bill/payment record(s). "
                        + "Your bills may already be uploaded — open Bills on your other Mac and refresh."
                    log(message, level: .success)
                    billsExportOutcome = .succeeded(recordCount: exportedCount)
                    return message
                }
            }
            return await messageForBillsExportTimeout(
                localRecordCount: exportedCount,
                timeoutSeconds: timeoutSeconds
            )
        case .cancelled:
            billsExportOutcome = .idle
            return "Upload cancelled."
        }
    }

    private func setExporting(_ exporting: Bool, for target: ActiveCloudKitUpload) {
        switch target {
        case .notes:
            isNotesSyncInProgress = exporting
            if exporting {
                notesSyncClearTask?.cancel()
                notesExportOutcome = .exporting
            }
        case .bills:
            isBillsSyncInProgress = exporting
            if exporting {
                billsSyncClearTask?.cancel()
                billsExportOutcome = .exporting
            }
        case .synced:
            isNotesSyncInProgress = exporting
            isBillsSyncInProgress = exporting
            if exporting {
                notesSyncClearTask?.cancel()
                billsSyncClearTask?.cancel()
                notesExportOutcome = .exporting
                billsExportOutcome = .exporting
            }
        }
    }

    private func setIdle(for target: ActiveCloudKitUpload) {
        switch target {
        case .notes:
            notesExportOutcome = .idle
        case .bills:
            billsExportOutcome = .idle
        case .synced:
            notesExportOutcome = .idle
            billsExportOutcome = .idle
        }
    }

    private func setFailed(_ message: String, for target: ActiveCloudKitUpload) {
        switch target {
        case .notes:
            notesExportOutcome = .failed(message)
        case .bills:
            billsExportOutcome = .failed(message)
        case .synced:
            notesExportOutcome = .failed(message)
            billsExportOutcome = .failed(message)
        }
    }

    private var isUploadWaitActive: Bool {
        switch activeUpload {
        case .notes:
            if case .exporting = notesExportOutcome { return true }
        case .bills:
            if case .exporting = billsExportOutcome { return true }
        case .synced:
            if case .exporting = notesExportOutcome { return true }
            if case .exporting = billsExportOutcome { return true }
        case .none:
            break
        }
        return false
    }

    private enum ExportWaitResult: Equatable {
        case completed
        case failed(Error)
        case timedOut
        case cancelled

        static func == (lhs: ExportWaitResult, rhs: ExportWaitResult) -> Bool {
            switch (lhs, rhs) {
            case (.completed, .completed), (.timedOut, .timedOut), (.cancelled, .cancelled):
                return true
            case (.failed(let left), .failed(let right)):
                return left.localizedDescription == right.localizedDescription
            default:
                return false
            }
        }
    }

    private func waitForCloudKitExport(timeoutSeconds: TimeInterval) async -> ExportWaitResult {
        await withCheckedContinuation { continuation in
            final class WaitState: @unchecked Sendable {
                var finished = false
                var observer: NSObjectProtocol?
                var timeoutWorkItem: DispatchWorkItem?
            }
            let state = WaitState()

            func finish(_ result: ExportWaitResult) {
                DispatchQueue.main.async { [weak self] in
                    guard !state.finished else { return }
                    state.finished = true
                    state.timeoutWorkItem?.cancel()
                    if let observer = state.observer {
                        NotificationCenter.default.removeObserver(observer)
                        state.observer = nil
                    }
                    if result == .timedOut {
                        self?.log(
                            "Export wait timed out — CloudKit did not send an export finished event",
                            level: .warning
                        )
                    }
                    continuation.resume(returning: result)
                }
            }

            state.observer = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event else {
                    return
                }
                guard event.type == .export else { return }

                if event.endDate == nil {
                    self?.log("CloudKit export started (upload wait)")
                    return
                }

                if let error = event.error {
                    finish(.failed(error))
                    return
                }

                self?.log("CloudKit export finished (upload wait)", level: .success)
                finish(.completed)
            }

            state.timeoutWorkItem = DispatchWorkItem {
                finish(.timedOut)
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + timeoutSeconds,
                execute: state.timeoutWorkItem!
            )
        }
    }

    private func messageForNotesExportTimeout(localNoteCount: Int, timeoutSeconds: TimeInterval) async -> String {
        let noteWord = localNoteCount == 1 ? "note" : "notes"

        if let lastCloudKitExportError {
            log("Last export error: \(lastCloudKitExportError)", level: .warning)
        }

        if let containerID = ubiquityContainerIdentifier {
            let summary = await CloudKitRecordDiagnostics.summarizeRemoteCounts(
                containerID: containerID,
                zoneName: NucleusDatabase.swiftDataCloudKitZoneName
            )
            log("CloudKit Production record counts: \(summary)", level: .info)
        }

        var message =
            "iCloud has 0 note records — your \(localNoteCount) local \(noteWord) did not upload. "

        if let lastCloudKitExportError {
            message += "Last export error: \(lastCloudKitExportError). "
        } else {
            message +=
                "CloudKit never sent an export finished event within \(Int(timeoutSeconds)) seconds. "
        }

        message += CloudKitRecordDiagnostics.productionSchemaDeployHint
        log(message, level: .warning)
        return message
    }

    private func messageForBillsExportTimeout(localRecordCount: Int, timeoutSeconds: TimeInterval) async -> String {
        let recordWord = localRecordCount == 1 ? "record" : "records"

        if let lastCloudKitExportError {
            log("Last export error: \(lastCloudKitExportError)", level: .warning)
        }

        if let containerID = ubiquityContainerIdentifier {
            let summary = await CloudKitRecordDiagnostics.summarizeRemoteCounts(
                containerID: containerID,
                zoneName: NucleusDatabase.swiftDataCloudKitZoneName
            )
            log("CloudKit Production record counts: \(summary)", level: .info)
        }

        var message =
            "iCloud has 0 bill/payment records — your \(localRecordCount) local bill/payment \(recordWord) did not upload. "

        if summaryContainsMissingBillTypes() {
            message +=
                "CD_BillRecord and CD_BillPaymentRecord are not deployed to Production yet. "
        }

        if let lastCloudKitExportError {
            message += "Last export error: \(lastCloudKitExportError). "
        } else {
            message +=
                "CloudKit never sent an export finished event within \(Int(timeoutSeconds)) seconds. "
        }

        message += CloudKitRecordDiagnostics.productionSchemaDeployHint
        log(message, level: .warning)
        return message
    }

    private func summaryContainsMissingBillTypes() -> Bool {
        syncLogStore.entries.contains { entry in
            entry.message.contains("CD_BillRecord") && entry.message.contains("unknownItem")
        }
    }

    private struct BillCloudKitCounts: Equatable {
        let bills: Int
        let payments: Int
    }

    private func countBillsInCloudKit() async -> BillCloudKitCounts? {
        guard let containerID = ubiquityContainerIdentifier else { return nil }

        let billCount = await CloudKitRecordDiagnostics.countRecords(
            containerID: containerID,
            zoneName: NucleusDatabase.swiftDataCloudKitZoneName,
            recordType: "CD_BillRecord"
        )
        let paymentCount = await CloudKitRecordDiagnostics.countRecords(
            containerID: containerID,
            zoneName: NucleusDatabase.swiftDataCloudKitZoneName,
            recordType: "CD_BillPaymentRecord"
        )

        switch (billCount, paymentCount) {
        case (.success(let bills), .success(let payments)):
            return BillCloudKitCounts(bills: bills, payments: payments)
        case (.failure(let error), _), (_, .failure(let error)):
            log("CloudKit bill query failed: \(CloudKitErrorDescriber.describe(error))", level: .warning)
            return nil
        }
    }

    private func countNotesInCloudKit() async -> Int? {
        guard let containerID = ubiquityContainerIdentifier else { return nil }

        switch await CloudKitRecordDiagnostics.countRecords(
            containerID: containerID,
            zoneName: NucleusDatabase.swiftDataCloudKitZoneName,
            recordType: "CD_NoteRecord"
        ) {
        case .success(let count):
            return count
        case .failure(let error):
            log("CloudKit note query failed: \(CloudKitErrorDescriber.describe(error))", level: .warning)
            return nil
        }
    }

    public func refreshAccountStatus() async {
        status = .checking
        log("Checking iCloud account status…")

        guard let containerID = ubiquityContainerIdentifier else {
            status = .unavailable
            iCloudAccountProfile = ICloudAccountProfile()
            return
        }

        if FileManager.default.ubiquityIdentityToken == nil {
            status = .noAccount
            iCloudAccountProfile = ICloudAccountProfile()
            return
        }

        let container = CKContainer(identifier: containerID)
        do {
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                status = .available
            case .noAccount:
                status = .noAccount
            case .restricted:
                status = .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                status = .temporarilyUnavailable
            @unknown default:
                status = .temporarilyUnavailable
            }
        } catch {
            status = .error(error.localizedDescription)
        }

        if status.isAvailable {
            iCloudAccountProfile = await ICloudAccountProfileFetcher.fetch(containerIdentifier: containerID)
            log("iCloud available — \(iCloudAccountDisplayName)", level: .success)
            await logCloudKitDiagnostics(containerID: containerID)
        } else {
            iCloudAccountProfile = ICloudAccountProfile()
            log("iCloud status: \(status.label)", level: .warning)
        }
    }

    private func logCloudKitDiagnostics(containerID: String) async {
        let container = CKContainer(identifier: containerID)
        do {
            let zones = try await container.privateCloudDatabase.allRecordZones()
            let zoneNames = zones.map(\.zoneID.zoneName).sorted().joined(separator: ", ")
            log("CloudKit private zones: \(zoneNames.isEmpty ? "(none)" : zoneNames)")
        } catch {
            log("CloudKit zone check failed: \(CloudKitErrorDescriber.describe(error))", level: .warning)
        }

        let summary = await CloudKitRecordDiagnostics.summarizeRemoteCounts(
            containerID: containerID,
            zoneName: NucleusDatabase.swiftDataCloudKitZoneName
        )
        log("CloudKit Production record counts: \(summary)")

        if summary.contains("CD_BillRecord=?") || summary.contains("CD_BillPaymentRecord=?") {
            log(
                "Bill record types are missing in CloudKit Production — deploy schema in CloudKit Console, then use Settings → iCloud → Upload Bills to iCloud.",
                level: .warning
            )
        }

        if summary.contains("CD_NoteRecord=0") {
            await logExportFailureHints(containerID: containerID)
        }
    }

    private func logExportFailureHints(containerID: String) async {
        let probeSummary = await CloudKitRecordDiagnostics.probeAllSyncedRecordTypes(
            containerID: containerID,
            zoneName: NucleusDatabase.swiftDataCloudKitZoneName
        )
        log("CloudKit write probes: \(probeSummary)", level: .info)

        if probeSummary.contains("FAILED") {
            log(
                "CloudKit rejected a test write — check iCloud storage in System Settings → Apple ID → iCloud, or deploy schema in CloudKit Console.",
                level: .warning
            )
            return
        }

        log(
            "CloudKit accepts direct writes — Production schema looks OK. Add notes, then Settings → iCloud → Upload Notes to iCloud. An export error on an empty database is usually harmless until you have data to sync.",
            level: .warning
        )
    }

    public func markNotesLocalChange() {
        isNotesSyncInProgress = true
        notesSyncClearTask?.cancel()
        notesSyncClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            isNotesSyncInProgress = false
        }
    }

    public var iCloudAccountDisplayName: String {
        if !iCloudAccountProfile.isEmpty {
            return iCloudAccountProfile.displayName
        }
        if FileManager.default.ubiquityIdentityToken != nil {
            return "Signed in to iCloud"
        }
        return "Not signed in to iCloud"
    }

    private func observeRemoteChanges() {
        guard remoteChangeObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRemoteChangeReload()
            }
        }
    }

    private func scheduleRemoteChangeReload() {
        lastRemoteChangeAt = Date()
        if isUploadWaitActive {
            log("Remote CloudKit change received during upload wait", level: .info)
        } else {
            isNotesSyncInProgress = false
            isBillsSyncInProgress = false
            notesSyncClearTask?.cancel()
            billsSyncClearTask?.cancel()
        }

        remoteChangeDebounceTask?.cancel()
        remoteChangeDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            log("Remote CloudKit change received — reloading synced data", level: .success)
            NotificationCenter.default.post(name: .nucleusCloudKitDataDidChange, object: nil)
        }
    }

    private func observeCloudKitExportEvents() {
        guard cloudKitExportObserver == nil else { return }
        cloudKitExportObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else {
                    return
                }

                self?.logCloudKitEvent(event)

                if event.type == .export {
                    if let error = event.error {
                        let message = Self.exportFailureMessage(error)
                        if case .exporting = self?.notesExportOutcome {
                            self?.notesExportOutcome = .failed(message)
                        }
                        if case .exporting = self?.billsExportOutcome {
                            self?.billsExportOutcome = .failed(message)
                        }
                        self?.isNotesSyncInProgress = false
                        self?.isBillsSyncInProgress = false
                        return
                    }

                    if event.endDate != nil {
                        if case .exporting = self?.notesExportOutcome {
                            self?.isNotesSyncInProgress = false
                        }
                        if case .exporting = self?.billsExportOutcome {
                            self?.isBillsSyncInProgress = false
                        }
                    }
                }
            }
        }
    }

    private func logCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        let phase = event.endDate == nil ? "started" : "finished"
        let typeLabel: String
        switch event.type {
        case .export:
            typeLabel = "export"
        case .import:
            typeLabel = "import"
        case .setup:
            typeLabel = "setup"
        @unknown default:
            typeLabel = "sync"
        }

        if let error = event.error {
            if event.type == .export, event.endDate != nil {
                lastCloudKitExportError = CloudKitErrorDescriber.describe(error)
            }
            log("CloudKit \(typeLabel) \(phase): \(CloudKitErrorDescriber.describe(error))", level: .error)
            return
        }

        if event.type == .export, event.endDate != nil {
            lastCloudKitExportError = nil
        }

        log("CloudKit \(typeLabel) \(phase)", level: event.endDate == nil ? .info : .success)
    }

    private nonisolated static func exportFailureMessage(_ error: Error) -> String {
        CloudKitErrorDescriber.userFacingUploadFailure(error)
    }
}
