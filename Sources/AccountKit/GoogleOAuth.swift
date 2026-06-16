import Foundation
import NucleusKit
import Security

public enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case itemNotFound
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode token payload."
        case .itemNotFound:
            return "Keychain item was not found."
        case .unexpectedStatus(let status):
            return "Keychain returned status \(status)."
        }
    }
}

public struct OAuthTokenBundle: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(60)
    }
}

public final class KeychainTokenStore: Sendable {
    public static let shared = KeychainTokenStore()
    private let service = "net.suherman.nucleus.oauth"

    private init() {}

    public func saveTokens(
        _ tokens: OAuthTokenBundle,
        accountID: UUID,
        synchronizable: Bool = true
    ) throws {
        let data = try JSONEncoder().encode(tokens)
        deleteTokens(accountID: accountID)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func loadTokens(accountID: UUID) throws -> OAuthTokenBundle {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            query.removeValue(forKey: kSecAttrSynchronizable as String)
            status = SecItemCopyMatching(query as CFDictionary, &item)
        }

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return try JSONDecoder().decode(OAuthTokenBundle.self, from: data)
    }

    public func deleteTokens(accountID: UUID) {
        for synchronizable in [kCFBooleanTrue, kCFBooleanFalse] as [CFTypeRef] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountID.uuidString,
                kSecAttrSynchronizable as String: synchronizable,
            ]
            SecItemDelete(query as CFDictionary)
        }

        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
        SecItemDelete(legacyQuery as CFDictionary)
    }

    public func hasTokens(accountID: UUID) -> Bool {
        (try? loadTokens(accountID: accountID)) != nil
    }

    public func deleteAllTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    public func migrateAllToSynchronizable(accountIDs: [UUID]) {
        for accountID in accountIDs {
            guard let tokens = try? loadTokens(accountID: accountID) else { continue }
            try? saveTokens(tokens, accountID: accountID, synchronizable: true)
        }
    }

    public func migrateAllToLocalOnly(accountIDs: [UUID]) {
        for accountID in accountIDs {
            guard let tokens = try? loadTokens(accountID: accountID) else { continue }
            try? saveTokens(tokens, accountID: accountID, synchronizable: false)
        }
    }
}

public enum GoogleOAuthScopes {
    public static let all: [String] = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/drive.file",
        "openid",
        "email",
        "profile",
    ]
}

public struct GoogleOAuthConfiguration: Sendable {
    public var clientID: String
    public var redirectURI: String

    public init(clientID: String, redirectURI: String = "net.suherman.nucleus:/oauth2redirect") {
        self.clientID = clientID
        self.redirectURI = redirectURI
    }

    public var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct GoogleUserProfile: Codable, Sendable {
    public var email: String
    public var name: String
    public var picture: String?
}

public enum GoogleOAuthClient {
    public static func authorizationURL(configuration: GoogleOAuthConfiguration) -> URL? {
        guard configuration.isConfigured else { return nil }
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthScopes.all.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
    }

    public static func exchangeCode(
        _ code: String,
        configuration: GoogleOAuthConfiguration,
        clientSecret: String? = nil
    ) async throws -> OAuthTokenBundle {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = [
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "client_id=\(configuration.clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? configuration.clientID)",
            "redirect_uri=\(configuration.redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? configuration.redirectURI)",
            "grant_type=authorization_code",
        ]
        if let clientSecret, !clientSecret.isEmpty {
            body.append("client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientSecret)")
        }
        request.httpBody = body.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let accessToken = json?["access_token"] as? String,
            let refreshToken = json?["refresh_token"] as? String,
            let expiresIn = json?["expires_in"] as? Double
        else {
            throw URLError(.cannotParseResponse)
        }

        return OAuthTokenBundle(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    public static func refreshTokens(
        _ refreshToken: String,
        configuration: GoogleOAuthConfiguration,
        clientSecret: String? = nil
    ) async throws -> OAuthTokenBundle {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = [
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)",
            "client_id=\(configuration.clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? configuration.clientID)",
            "grant_type=refresh_token",
        ]
        if let clientSecret, !clientSecret.isEmpty {
            body.append("client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientSecret)")
        }
        request.httpBody = body.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let accessToken = json?["access_token"] as? String,
            let expiresIn = json?["expires_in"] as? Double
        else {
            throw URLError(.cannotParseResponse)
        }

        return OAuthTokenBundle(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    public static func fetchProfile(accessToken: String) async throws -> GoogleUserProfile {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GoogleUserProfile.self, from: data)
    }
}

public actor AccountSessionStore {
    public static let shared = AccountSessionStore()

    private var configuration = GoogleOAuthConfiguration(clientID: "")
    private var clientSecret: String?
    private var tokenSynchronizable = true

    public func updateConfiguration(
        _ configuration: GoogleOAuthConfiguration,
        clientSecret: String? = nil,
        tokenSynchronizable: Bool = true
    ) {
        self.configuration = configuration
        self.clientSecret = clientSecret
        self.tokenSynchronizable = tokenSynchronizable
    }

    public func currentConfiguration() -> GoogleOAuthConfiguration {
        configuration
    }

    public func validAccessToken(accountID: UUID) async throws -> String {
        let tokens = try KeychainTokenStore.shared.loadTokens(accountID: accountID)
        if !tokens.isExpired {
            return tokens.accessToken
        }
        let refreshed = try await GoogleOAuthClient.refreshTokens(
            tokens.refreshToken,
            configuration: configuration,
            clientSecret: clientSecret
        )
        try KeychainTokenStore.shared.saveTokens(
            refreshed,
            accountID: accountID,
            synchronizable: tokenSynchronizable
        )
        return refreshed.accessToken
    }
}
