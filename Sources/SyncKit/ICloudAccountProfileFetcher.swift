import CloudKit
import Foundation

public struct ICloudAccountProfile: Sendable, Equatable {
    public var fullName: String?
    public var email: String?

    public init(fullName: String? = nil, email: String? = nil) {
        self.fullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.email = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var displayName: String {
        if let email { return email }
        if let fullName { return fullName }
        return "Signed in to iCloud"
    }

    public var isEmpty: Bool {
        fullName == nil && email == nil
    }
}

public enum ICloudAccountProfileFetcher {
    public static func fetch(
        containerIdentifier: String = "iCloud.net.suherman.nucleus"
    ) async -> ICloudAccountProfile {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return ICloudAccountProfile()
        }

        let container = CKContainer(identifier: containerIdentifier)
        do {
            guard try await container.accountStatus() == .available else {
                return ICloudAccountProfile()
            }

            let recordID = try await container.userRecordID()
            var profile = ICloudAccountProfile()

            if let identity = try await container.userIdentity(forUserRecordID: recordID) {
                profile = merge(profile, with: makeProfile(from: identity))
            }

            if profile.fullName == nil,
               let recordProfile = await fetchNameFromUserRecord(container: container, recordID: recordID) {
                profile = merge(profile, with: recordProfile)
            }

            return profile
        } catch {
            return ICloudAccountProfile()
        }
    }

    private static func fetchNameFromUserRecord(
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
