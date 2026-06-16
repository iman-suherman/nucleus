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
    @Published public private(set) var syncLogStore = CloudKitSyncLogStore.shared

    private let ubiquityContainerIdentifier: String?
    private var remoteChangeObserver: NSObjectProtocol?
    private var cloudKitExportObserver: NSObjectProtocol?
    private var notesSyncClearTask: Task<Void, Never>?

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
        log("Upload Notes to iCloud requested")
        isNotesSyncInProgress = true
        notesSyncClearTask?.cancel()
        notesExportOutcome = .exporting

        async let exportWait = waitForCloudKitExport(timeoutSeconds: timeoutSeconds)

        // Let the export listener register before we save and trigger CloudKit.
        await Task.yield()
        await Task.yield()

        let exportedCount: Int
        do {
            log("Queuing local notes for CloudKit export…")
            exportedCount = try performExport()
            log("Marked \(exportedCount) note(s) for export")
        } catch {
            isNotesSyncInProgress = false
            notesExportOutcome = .failed(error.localizedDescription)
            log("Failed to queue notes: \(error.localizedDescription)", level: .error)
            return error.localizedDescription
        }

        guard exportedCount > 0 else {
            isNotesSyncInProgress = false
            notesExportOutcome = .idle
            log("No notes needed re-export — already queued", level: .warning)
            return "Notes are already queued for iCloud sync."
        }

        log("Waiting for CloudKit export (timeout \(Int(timeoutSeconds))s)…")

        let exportEvent = await exportWait
        isNotesSyncInProgress = false

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
            let message =
                "Queued \(exportedCount) \(noteWord) locally, but CloudKit did not confirm export within \(Int(timeoutSeconds)) seconds. "
                + "Check the sync log for export errors, confirm Production schema in CloudKit Console, then try again."
            log(message, level: .warning)
            return message
        case .cancelled:
            notesExportOutcome = .idle
            return "Upload cancelled."
        }
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

    private func countNotesInCloudKit() async -> Int? {
        guard let containerID = ubiquityContainerIdentifier else { return nil }

        let container = CKContainer(identifier: containerID)
        let zoneID = CKRecordZone.ID(
            zoneName: NucleusDatabase.swiftDataCloudKitZoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let query = CKQuery(recordType: "CD_NoteRecord", predicate: NSPredicate(value: true))

        do {
            let (results, _) = try await container.privateCloudDatabase.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: []
            )
            return results.count
        } catch {
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
                guard let self else { return }
                self.lastRemoteChangeAt = Date()
                if case .exporting = self.notesExportOutcome {
                    self.log("Remote CloudKit change received during upload wait", level: .info)
                } else {
                    self.isNotesSyncInProgress = false
                    self.notesSyncClearTask?.cancel()
                }
                self.log("Remote CloudKit change received — reloading notes", level: .success)
                NotificationCenter.default.post(name: .nucleusCloudKitDataDidChange, object: nil)
            }
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
                        self?.notesExportOutcome = .failed(message)
                        self?.isNotesSyncInProgress = false
                        return
                    }

                    if event.endDate != nil, case .exporting = self?.notesExportOutcome {
                        self?.isNotesSyncInProgress = false
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
            log("CloudKit \(typeLabel) \(phase): \(CloudKitErrorDescriber.describe(error))", level: .error)
            return
        }

        log("CloudKit \(typeLabel) \(phase)", level: event.endDate == nil ? .info : .success)
    }

    private nonisolated static func exportFailureMessage(_ error: Error) -> String {
        CloudKitErrorDescriber.userFacingUploadFailure(error)
    }
}
