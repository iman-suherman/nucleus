import Foundation
import NucleusKit

public enum NucleusCloudAPIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(String)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Nucleus Cloud URL is invalid."
        case .unauthorized:
            return "Nucleus Cloud session expired. Connect again from Settings."
        case .serverError(let message):
            return message
        case .decodingFailed:
            return "Failed to decode Nucleus Cloud response."
        }
    }
}

public struct NucleusCloudConfiguration: Sendable {
    public static let productionBaseURL = URL(string: "https://nucleus-sync.suherman.net")!
    public static let localBaseURL = URL(string: "http://127.0.0.1:3000")!

    public var baseURL: URL

    public init(baseURL: URL = productionBaseURL) {
        self.baseURL = baseURL
    }
}

struct SyncNoteDTO: Codable {
    var clientId: String
    var title: String
    var markdown: String
    var folderRaw: String
    var driveFileId: String?
    var updatedAt: String
    var deletedAt: String?
    var version: Int
}

struct SyncBillDTO: Codable {
    var clientId: String
    var name: String
    var amount: Double
    var currencyCode: String?
    var categoryRaw: String
    var recurrenceRaw: String
    var customIntervalDays: Int?
    var dueDayOfMonth: Int?
    var nextDueDate: String
    var iconName: String
    var notes: String
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var version: Int
}

struct SyncBillPaymentDTO: Codable {
    var clientId: String
    var billClientId: String
    var amount: Double
    var paidAt: String
    var note: String
    var updatedAt: String
    var deletedAt: String?
    var version: Int
}

struct SyncGoogleAccountDTO: Codable {
    var clientId: String
    var email: String
    var displayName: String
    var avatarUrl: String
    var isPrimary: Bool
    var isPrimaryNotesAccount: Bool
    var authMode: String
    var sortOrder: Int
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var version: Int
}

struct SyncSettingsDTO: Codable {
    var payload: NucleusSyncedConfiguration
    var updatedAt: String
    var version: Int
}

struct SyncDashboardDTO: Codable {
    var payload: StoredDashboardAnalysis
    var analyzedAt: String
    var updatedAt: String
    var version: Int
}

struct SyncPullResponse: Codable {
    var serverTime: String
    var notes: [SyncNoteDTO]?
    var bills: [SyncBillDTO]?
    var billPayments: [SyncBillPaymentDTO]?
    var settings: SyncSettingsDTO?
    var dashboard: SyncDashboardDTO?
    var googleAccounts: [SyncGoogleAccountDTO]?
}

struct SyncPushPayload: Codable {
    var notes: [SyncNoteDTO]?
    var bills: [SyncBillDTO]?
    var billPayments: [SyncBillPaymentDTO]?
    var settings: SyncSettingsDTO?
    var dashboard: SyncDashboardDTO?
    var googleAccounts: [SyncGoogleAccountDTO]?
}

struct DeviceAuthorizationRequest: Codable {
    var deviceId: String
    var deviceName: String
}

struct DeviceAuthorizationResponse: Codable {
    var deviceId: String
    var verificationUrl: String
    var expiresAt: String
}

struct DevicePollResponse: Codable {
    var status: String
    var token: String?
}

struct AccountResponse: Codable {
    var authenticated: Bool
    var user: AccountUser?
}

struct AccountUser: Codable {
    var id: String
    var email: String
    var name: String
    var avatarUrl: String
}

public actor NucleusCloudAPIClient {
    static let shared = NucleusCloudAPIClient()

    private let configuration: NucleusCloudConfiguration
    private let session: URLSession
    private let isoFormatter = ISO8601DateFormatter()

    init(configuration: NucleusCloudConfiguration = NucleusCloudConfiguration(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func beginDeviceAuthorization() async throws -> DeviceAuthorizationResponse {
        let url = configuration.baseURL.appending(path: "/api/v1/auth/device")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = DeviceAuthorizationRequest(
            deviceId: NucleusCloudDeviceIdentity.deviceID,
            deviceName: NucleusCloudDeviceIdentity.deviceName
        )
        request.httpBody = try JSONEncoder().encode(body)

        return try await decode(DeviceAuthorizationResponse.self, request: request)
    }

    func pollDeviceAuthorization() async throws -> DevicePollResponse {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "/api/v1/auth/device"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "device_id", value: NucleusCloudDeviceIdentity.deviceID),
        ]
        guard let url = components?.url else { throw NucleusCloudAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await decode(DevicePollResponse.self, request: request)
    }

    func fetchAccount(apiToken: String) async throws -> AccountUser {
        var request = URLRequest(url: configuration.baseURL.appending(path: "/api/v1/account"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let response = try await decode(AccountResponse.self, request: request)
        guard let user = response.user else {
            throw NucleusCloudAPIError.unauthorized
        }
        return user
    }

    func pull(apiToken: String, since: Date?) async throws -> SyncPullResponse {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "/api/v1/sync/pull"),
            resolvingAgainstBaseURL: false
        )
        if let since {
            components?.queryItems = [URLQueryItem(name: "since", value: isoFormatter.string(from: since))]
        }
        guard let url = components?.url else { throw NucleusCloudAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        return try await decode(SyncPullResponse.self, request: request)
    }

    func push(apiToken: String, payload: SyncPushPayload) async throws {
        var request = URLRequest(url: configuration.baseURL.appending(path: "/api/v1/sync/push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NucleusCloudAPIError.serverError("Invalid response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw NucleusCloudAPIError.serverError("Push failed with status \(http.statusCode)")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NucleusCloudAPIError.serverError("Invalid response")
        }

        if http.statusCode == 401 {
            throw NucleusCloudAPIError.unauthorized
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw NucleusCloudAPIError.serverError(message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NucleusCloudAPIError.decodingFailed
        }
    }
}
