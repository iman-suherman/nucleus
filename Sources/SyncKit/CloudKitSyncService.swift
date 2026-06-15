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
            case .error(let message):
                return message
            }
        }
    }

    @Published public private(set) var status: SyncStatus = .checking
    @Published public private(set) var lastRemoteChangeAt: Date?

    private let container: CKContainer
    private var remoteChangeObserver: NSObjectProtocol?

    public init(containerIdentifier: String = "iCloud.net.suherman.nucleus") {
        container = CKContainer(identifier: containerIdentifier)
    }

    public func start() {
        observeRemoteChanges()
        Task { await refreshAccountStatus() }
    }

    public func refreshAccountStatus() async {
        status = .checking
        do {
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                status = .available
            case .noAccount:
                status = .noAccount
            case .restricted:
                status = .restricted
            case .couldNotDetermine:
                status = .error("Could not determine iCloud status")
            case .temporarilyUnavailable:
                status = .temporarilyUnavailable
            @unknown default:
                status = .error("Unknown iCloud status")
            }
        } catch {
            status = .error(error.localizedDescription)
        }
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
                NotificationCenter.default.post(name: .nucleusCloudKitDataDidChange, object: nil)
            }
        }
    }
}
