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

    private let ubiquityContainerIdentifier: String?
    private var remoteChangeObserver: NSObjectProtocol?

    public init(ubiquityContainerIdentifier: String? = "iCloud.net.suherman.nucleus") {
        self.ubiquityContainerIdentifier = ubiquityContainerIdentifier
    }

    public func start() {
        observeRemoteChanges()
        Task { await refreshAccountStatus() }
    }

    public func refreshAccountStatus() async {
        status = .checking

        guard ubiquityContainerIdentifier != nil else {
            status = .unavailable
            return
        }

        if FileManager.default.ubiquityIdentityToken == nil {
            status = .noAccount
            return
        }

        if let containerID = ubiquityContainerIdentifier,
           FileManager.default.url(forUbiquityContainerIdentifier: containerID) == nil {
            status = .temporarilyUnavailable
            return
        }

        status = .available
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
