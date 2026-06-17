import Combine
import Foundation
import SyncKit

/// Surfaces iCloud / CloudKit sync state for mobile UI.
@MainActor
public final class ICloudSyncDisplayService: ObservableObject {
    public static let shared = ICloudSyncDisplayService()

    public let containerIdentifier = NucleusAppIdentity.iCloudContainerIdentifier

    @Published public private(set) var syncStatus: CloudKitSyncService.SyncStatus = .checking
    @Published public private(set) var isSignedIn = false
    @Published public private(set) var accountName: String?
    @Published public private(set) var lastRemoteChangeAt: Date?

    private let syncService = CloudKitSyncService.shared
    private var lastRemoteObserver: AnyCancellable?

    private init() {
        lastRemoteObserver = syncService.$lastRemoteChangeAt
            .receive(on: RunLoop.main)
            .sink { [weak self] date in
                self?.lastRemoteChangeAt = date
            }
    }

    public func refresh() async {
        await syncService.refreshAccountStatus()
        syncStatus = syncService.status
        isSignedIn = FileManager.default.ubiquityIdentityToken != nil

        #if os(iOS)
        let profile = await ICloudAccountEmailResolver.fetchProfile(
            containerIdentifier: containerIdentifier
        )
        accountName = profile.fullName
        #else
        accountName = nil
        #endif

        lastRemoteChangeAt = syncService.lastRemoteChangeAt
    }

    public var accountDisplayName: String {
        if let accountName, !accountName.isEmpty {
            return accountName
        }
        if isSignedIn {
            return "Signed in to iCloud"
        }
        return "Not signed in"
    }

    public var statusLabel: String {
        syncStatus.label
    }

    public var isSyncAvailable: Bool {
        syncStatus.isAvailable
    }
}
