import Foundation

public struct ICloudAccountProfile: Sendable, Equatable {
    public var fullName: String?
    public var email: String?

    public init(fullName: String? = nil, email: String? = nil) {
        self.fullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.email = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var isEmpty: Bool {
        fullName == nil && email == nil
    }
}

enum ICloudAccountEmailResolver {
    static func fetchProfile(containerIdentifier: String = "iCloud.net.suherman.nucleus") async -> ICloudAccountProfile {
        #if os(iOS)
        return await fetchProfileOnIOS(containerIdentifier: containerIdentifier)
        #else
        return ICloudAccountProfile()
        #endif
    }
}

#if os(iOS)
import CloudKit
#if canImport(Accounts)
import Accounts
#endif

extension ICloudAccountEmailResolver {
    private static let accountTypeIdentifiers = [
        "com.apple.iCloud",
        "com.apple.account.iCloud",
        "com.apple.CloudKit",
    ]

    fileprivate static func fetchProfileOnIOS(containerIdentifier: String) async -> ICloudAccountProfile {
        if let profile = await fetchProfileViaAccounts(), !profile.isEmpty {
            return profile
        }
        if let profile = await fetchProfileViaCloudKit(containerIdentifier: containerIdentifier), !profile.isEmpty {
            return profile
        }
        if let defaultID = CKContainer.default().containerIdentifier,
           defaultID != containerIdentifier,
           let profile = await fetchProfileViaCloudKit(containerIdentifier: defaultID),
           !profile.isEmpty {
            return profile
        }
        return ICloudAccountProfile()
    }

    @MainActor
    private static func fetchProfileViaAccounts() async -> ICloudAccountProfile? {
        #if canImport(Accounts)
        let store = ACAccountStore()

        for identifier in accountTypeIdentifiers {
            guard let accountType = store.accountType(withAccountTypeIdentifier: identifier) else { continue }

            if let profile = profile(from: store.accounts(with: accountType)), !profile.isEmpty {
                return profile
            }

            let granted = await requestAccountAccess(store: store, accountType: accountType)
            if granted, let profile = profile(from: store.accounts(with: accountType)), !profile.isEmpty {
                return profile
            }
        }
        #endif
        return nil
    }

    #if canImport(Accounts)
    @MainActor
    private static func requestAccountAccess(store: ACAccountStore, accountType: ACAccountType) async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestAccessToAccounts(with: accountType, options: nil) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func profile(from accounts: [Any]?) -> ICloudAccountProfile? {
        guard let accounts else { return nil }
        for case let account as ACAccount in accounts {
            let email = account.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = account.accountDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = ICloudAccountProfile(
                fullName: name,
                email: email?.contains("@") == true ? email : nil
            )
            if !resolved.isEmpty {
                return resolved
            }
        }
        return nil
    }
    #endif

    private static func fetchProfileViaCloudKit(containerIdentifier: String) async -> ICloudAccountProfile? {
        guard FileManager.default.ubiquityIdentityToken != nil else { return nil }

        let container = CKContainer(identifier: containerIdentifier)
        do {
            guard try await container.accountStatus() == .available else { return nil }
            let recordID = try await container.userRecordID()

            await ensureDiscoverabilityPermission(for: container)

            var profile = ICloudAccountProfile()

            if let participantProfile = await fetchProfileFromShareParticipant(container: container, recordID: recordID) {
                profile = participantProfile
            }

            if let identity = try await container.userIdentity(forUserRecordID: recordID) {
                profile = merge(profile, with: makeProfile(from: identity))
            }

            if profile.fullName == nil || profile.email == nil,
               let recordProfile = await fetchProfileFromUserRecord(container: container, recordID: recordID) {
                profile = merge(profile, with: recordProfile)
            }

            return profile.isEmpty ? nil : profile
        } catch {
            return nil
        }
    }

    private static func ensureDiscoverabilityPermission(for container: CKContainer) async {
        do {
            let permissionStatus = try await container.applicationPermissionStatus(for: .userDiscoverability)
            if permissionStatus == .initialState {
                _ = try await container.requestApplicationPermission(.userDiscoverability)
            }
        } catch {
            return
        }
    }

    private static func fetchProfileFromShareParticipant(
        container: CKContainer,
        recordID: CKRecord.ID
    ) async -> ICloudAccountProfile? {
        await withCheckedContinuation { continuation in
            container.fetchShareParticipant(withUserRecordID: recordID) { participant, _ in
                if let participant {
                    continuation.resume(returning: makeProfile(from: participant.userIdentity))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func fetchProfileFromUserRecord(
        container: CKContainer,
        recordID: CKRecord.ID
    ) async -> ICloudAccountProfile? {
        do {
            let record = try await container.privateCloudDatabase.record(for: recordID)
            let firstName = record["firstName"] as? String
            let lastName = record["lastName"] as? String
            let composedName = [firstName, lastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: " ")
                .nilIfEmpty
            return ICloudAccountProfile(fullName: composedName, email: nil)
        } catch {
            return nil
        }
    }

    private static func makeProfile(from identity: CKUserIdentity) -> ICloudAccountProfile {
        let email = identity.lookupInfo?.emailAddress
        let name = formattedName(from: identity.nameComponents)
        return ICloudAccountProfile(fullName: name, email: email)
    }

    private static func formattedName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        return PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func merge(_ lhs: ICloudAccountProfile, with rhs: ICloudAccountProfile) -> ICloudAccountProfile {
        ICloudAccountProfile(
            fullName: lhs.fullName ?? rhs.fullName,
            email: lhs.email ?? rhs.email
        )
    }
}
#endif
