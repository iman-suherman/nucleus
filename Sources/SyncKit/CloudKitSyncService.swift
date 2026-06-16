import CloudKit
import Combine
import CoreData
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
        Task { await refreshAccountStatus() }
    }

    /// Registers for the next CloudKit export, runs `performExport`, then waits for completion.
    public func queueNotesExportAndWait(
        performExport: @escaping @MainActor () throws -> Int,
        timeoutSeconds: TimeInterval = 60
    ) async -> String {
        enum ExportEvent {
            case completed
            case failed(Error)
        }

        isNotesSyncInProgress = true
        notesSyncClearTask?.cancel()
        notesExportOutcome = .exporting

        var exportedCount = 0

        let exportEvent: ExportEvent? = await withTaskGroup(of: ExportEvent?.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (continuation: CheckedContinuation<ExportEvent?, Never>) in
                    final class Handle: @unchecked Sendable {
                        var observer: NSObjectProtocol?
                        var resumed = false
                    }
                    let handle = Handle()

                    func resumeOnce(_ event: ExportEvent?) {
                        Task { @MainActor in
                            guard !handle.resumed else { return }
                            handle.resumed = true
                            if let observer = handle.observer {
                                NotificationCenter.default.removeObserver(observer)
                            }
                            continuation.resume(returning: event)
                        }
                    }

                    handle.observer = NotificationCenter.default.addObserver(
                        forName: NSPersistentCloudKitContainer.eventChangedNotification,
                        object: nil,
                        queue: .main
                    ) { notification in
                        Task { @MainActor in
                            guard let event = notification.userInfo?[
                                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                            ] as? NSPersistentCloudKitContainer.Event else {
                                return
                            }
                            guard event.type == .export else { return }

                            if let error = event.error {
                                resumeOnce(.failed(error))
                                return
                            }

                            if event.endDate != nil {
                                resumeOnce(.completed)
                            }
                        }
                    }

                    Task { @MainActor in
                        do {
                            exportedCount = try performExport()
                            if exportedCount == 0 {
                                resumeOnce(nil)
                            }
                        } catch {
                            resumeOnce(.failed(error))
                        }
                    }
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }

            var outcome: ExportEvent?
            for await value in group {
                if let value {
                    outcome = value
                    group.cancelAll()
                    break
                }
                outcome = nil
                group.cancelAll()
                break
            }
            return outcome
        }

        isNotesSyncInProgress = false

        if exportedCount == 0 {
            notesExportOutcome = .idle
            return "Notes are already queued for iCloud sync."
        }

        let noteWord = exportedCount == 1 ? "note" : "notes"

        switch exportEvent {
        case .completed:
            notesExportOutcome = .succeeded(noteCount: exportedCount)
            return "Uploaded \(exportedCount) \(noteWord) to iCloud."
        case .failed(let error):
            let message = Self.exportFailureMessage(error)
            notesExportOutcome = .failed(message)
            return message
        case nil:
            let message =
                "Queued \(exportedCount) \(noteWord) for iCloud, but upload has not finished after \(Int(timeoutSeconds)) seconds. "
                + "Leave Nucleus open, confirm iCloud is signed in, then try again."
            notesExportOutcome = .timedOut(noteCount: exportedCount)
            return message
        }
    }

    public func refreshAccountStatus() async {
        status = .checking

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
        } else {
            iCloudAccountProfile = ICloudAccountProfile()
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
                self?.lastRemoteChangeAt = Date()
                self?.isNotesSyncInProgress = false
                self?.notesSyncClearTask?.cancel()
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
                guard event.type == .export else { return }

                if let error = event.error {
                    let message = Self.exportFailureMessage(error)
                    self?.notesExportOutcome = .failed(message)
                    self?.isNotesSyncInProgress = false
                    return
                }

                if event.endDate != nil, case .exporting = self?.notesExportOutcome {
                    // Manual upload flow sets the final message; background exports just clear progress.
                    self?.isNotesSyncInProgress = false
                }
            }
        }
    }

    private nonisolated static func exportFailureMessage(_ error: Error) -> String {
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("schema") {
            return "iCloud upload failed: CloudKit schema is not deployed to Production. "
                + "Deploy the schema in CloudKit Console, then try again."
        }
        return "iCloud upload failed: \(description)"
    }
}
