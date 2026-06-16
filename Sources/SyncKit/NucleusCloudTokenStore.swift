import Foundation
import Security

public enum NucleusCloudTokenError: Error, LocalizedError {
    case encodingFailed
    case itemNotFound
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode Nucleus Cloud credentials."
        case .itemNotFound:
            return "Nucleus Cloud is not connected on this Mac."
        case .unexpectedStatus(let status):
            return "Keychain returned status \(status)."
        }
    }
}

public struct NucleusCloudCredentials: Codable, Sendable {
    public var apiToken: String
    public var userEmail: String
    public var userName: String
    public var connectedAt: Date

    public init(apiToken: String, userEmail: String, userName: String, connectedAt: Date = Date()) {
        self.apiToken = apiToken
        self.userEmail = userEmail
        self.userName = userName
        self.connectedAt = connectedAt
    }
}

public final class NucleusCloudTokenStore: Sendable {
    public static let shared = NucleusCloudTokenStore()

    private let service = "net.suherman.nucleus.cloud"
    private let account = "primary"

    private init() {}

    public func save(_ credentials: NucleusCloudCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NucleusCloudTokenError.unexpectedStatus(status)
        }
    }

    public func load() throws -> NucleusCloudCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            throw NucleusCloudTokenError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw NucleusCloudTokenError.unexpectedStatus(status)
        }

        guard let data = item as? Data else {
            throw NucleusCloudTokenError.encodingFailed
        }

        return try JSONDecoder().decode(NucleusCloudCredentials.self, from: data)
    }

    public var hasCredentials: Bool {
        (try? load()) != nil
    }

    public func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum NucleusCloudDeviceIdentity {
    private static let defaultsKey = "net.suherman.nucleus.cloud.deviceId"

    public static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: defaultsKey)
        return generated
    }

    public static var deviceName: String {
        Host.current().localizedName ?? "Nucleus Mac"
    }
}
