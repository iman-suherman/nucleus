import CloudKit
import Combine
import CoreData
import Foundation

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

    private let ubiquityContainerIdentifier: String?
    private var remoteChangeObserver: NSObjectProtocol?
    private var notesSyncClearTask: Task<Void, Never>?

    public init(ubiquityContainerIdentifier: String? = "iCloud.net.suherman.nucleus") {
        self.ubiquityContainerIdentifier = ubiquityContainerIdentifier
    }

    public func start() {
        observeRemoteChanges()
        Task { await refreshAccountStatus() }
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
}
