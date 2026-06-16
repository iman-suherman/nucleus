import Combine
import DatabaseKit
import Foundation
import NucleusKit
import SwiftData

public extension Notification.Name {
    static let nucleusCloudSyncDidChange = Notification.Name("NucleusCloudSyncDidChange")
    static let nucleusCloudDidConnect = Notification.Name("NucleusCloudDidConnect")
    static let nucleusDidOpenURL = Notification.Name("NucleusDidOpenURL")
}

@MainActor
public final class NucleusCloudSyncService: ObservableObject {
    public static let shared = NucleusCloudSyncService()

    public enum Status: Equatable {
        case disconnected
        case connecting
        case connected(email: String)
        case syncing
        case error(String)

        public var label: String {
            switch self {
            case .disconnected:
                return "Not connected"
            case .connecting:
                return "Waiting for browser authorization…"
            case .connected(let email):
                return "Connected as \(email)"
            case .syncing:
                return "Syncing with Nucleus Cloud…"
            case .error(let message):
                return message
            }
        }

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    @Published public private(set) var status: Status = .disconnected
    @Published public private(set) var lastSyncAt: Date?
    @Published public private(set) var lastError: String?

    private let api = NucleusCloudAPIClient.shared
    private let tokenStore = NucleusCloudTokenStore.shared
    private let defaultsKey = "net.suherman.nucleus.cloud.lastSyncAt"
    private var pollTask: Task<Void, Never>?
    private var verificationURL: URL?

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init() {
        lastSyncAt = UserDefaults.standard.object(forKey: defaultsKey) as? Date
        restoreConnectionIfPossible()
    }

    public func restoreConnectionIfPossible() {
        guard let credentials = try? tokenStore.load() else {
            status = .disconnected
            return
        }
        status = .connected(email: credentials.userEmail)
    }

    public func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        verificationURL = nil
        tokenStore.delete()
        status = .disconnected
        lastSyncAt = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    public func beginConnect() async throws -> URL {
        status = .connecting
        lastError = nil

        let response = try await api.beginDeviceAuthorization()
        guard let url = URL(string: response.verificationUrl) else {
            throw NucleusCloudAPIError.invalidURL
        }

        verificationURL = url
        startPolling()
        return url
    }

    public func handleDeepLinkToken(_ token: String) async throws {
        let user = try await api.fetchAccount(apiToken: token)
        try tokenStore.save(
            NucleusCloudCredentials(
                apiToken: token,
                userEmail: user.email,
                userName: user.name
            )
        )
        pollTask?.cancel()
        pollTask = nil
        status = .connected(email: user.email)
    }

    public func syncNow(context: ModelContext) async {
        guard let credentials = try? tokenStore.load() else {
            status = .disconnected
            return
        }

        status = .syncing
        lastError = nil

        do {
            let pushPayload = try buildPushPayload(context: context)
            try await api.push(apiToken: credentials.apiToken, payload: pushPayload)

            let since = lastSyncAt ?? Date(timeIntervalSince1970: 0)
            let pull = try await api.pull(apiToken: credentials.apiToken, since: since)
            try applyPullResponse(pull, context: context)

            let syncedAt = Date()
            lastSyncAt = syncedAt
            UserDefaults.standard.set(syncedAt, forKey: defaultsKey)
            status = .connected(email: credentials.userEmail)
            NotificationCenter.default.post(name: .nucleusCloudSyncDidChange, object: nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            status = .error(message)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }

                do {
                    let response = try await api.pollDeviceAuthorization()
                    if response.status == "approved", let token = response.token {
                        try await handleDeepLinkToken(token)
                        NotificationCenter.default.post(name: .nucleusCloudDidConnect, object: nil)
                        return
                    }
                    if response.status == "expired" {
                        status = .error("Browser authorization expired. Try again.")
                        return
                    }
                } catch {
                    // Keep polling until timeout; surface only persistent failures later.
                }
            }
        }
    }

    private func buildPushPayload(context: ModelContext) throws -> SyncPushPayload {
        let noteRecords = try context.fetch(FetchDescriptor<NoteRecord>())
        let billRecords = try context.fetch(FetchDescriptor<BillRecord>())
        let paymentRecords = try context.fetch(FetchDescriptor<BillPaymentRecord>())
        let accountRecords = try context.fetch(FetchDescriptor<GoogleAccountRecord>())
        let settingsRecords = try context.fetch(FetchDescriptor<SyncedSettingsRecord>())
        let dashboardRecords = try context.fetch(FetchDescriptor<DashboardAnalysisRecord>())

        var payload = SyncPushPayload()
        payload.notes = noteRecords.map { record in
            SyncNoteDTO(
                clientId: record.id.uuidString.lowercased(),
                title: record.title,
                markdown: record.markdown,
                folderRaw: record.folderRaw,
                driveFileId: record.driveFileID,
                updatedAt: isoFormatter.string(from: record.updatedAt),
                deletedAt: nil,
                version: Int(record.updatedAt.timeIntervalSince1970)
            )
        }

        payload.bills = billRecords.map { record in
            SyncBillDTO(
                clientId: record.id.uuidString.lowercased(),
                name: record.name,
                amount: record.amount,
                currencyCode: record.currencyCode,
                categoryRaw: record.categoryRaw,
                recurrenceRaw: record.recurrenceRaw,
                customIntervalDays: record.customIntervalDays,
                dueDayOfMonth: record.dueDayOfMonth,
                nextDueDate: isoFormatter.string(from: record.nextDueDate),
                iconName: record.iconName,
                notes: record.notes,
                isArchived: record.isArchived,
                sortOrder: record.sortOrder,
                createdAt: isoFormatter.string(from: record.createdAt),
                updatedAt: isoFormatter.string(from: record.createdAt),
                deletedAt: record.isArchived ? isoFormatter.string(from: Date()) : nil,
                version: Int(record.createdAt.timeIntervalSince1970)
            )
        }

        payload.billPayments = paymentRecords.map { record in
            SyncBillPaymentDTO(
                clientId: record.id.uuidString.lowercased(),
                billClientId: record.billID.uuidString.lowercased(),
                amount: record.amount,
                paidAt: isoFormatter.string(from: record.paidAt),
                note: record.note,
                updatedAt: isoFormatter.string(from: record.paidAt),
                deletedAt: nil,
                version: Int(record.paidAt.timeIntervalSince1970)
            )
        }

        payload.googleAccounts = accountRecords.map { record in
            SyncGoogleAccountDTO(
                clientId: record.id.uuidString.lowercased(),
                email: record.email,
                displayName: record.displayName,
                avatarUrl: record.avatarURL,
                isPrimary: record.isPrimary,
                isPrimaryNotesAccount: record.isPrimaryNotesAccount,
                authMode: record.authMode,
                sortOrder: record.sortOrder,
                createdAt: isoFormatter.string(from: record.createdAt),
                updatedAt: isoFormatter.string(from: record.createdAt),
                deletedAt: nil,
                version: Int(record.createdAt.timeIntervalSince1970)
            )
        }

        if let settings = settingsRecords.first {
            let configuration = try settings.configuration
            payload.settings = SyncSettingsDTO(
                payload: configuration,
                updatedAt: isoFormatter.string(from: settings.updatedAt),
                version: Int(settings.updatedAt.timeIntervalSince1970)
            )
        }

        if let dashboard = dashboardRecords.first {
            let stored = try dashboard.storedAnalysis
            payload.dashboard = SyncDashboardDTO(
                payload: stored,
                analyzedAt: isoFormatter.string(from: dashboard.analyzedAt),
                updatedAt: isoFormatter.string(from: dashboard.updatedAt),
                version: Int(dashboard.updatedAt.timeIntervalSince1970)
            )
        }

        return payload
    }

    private func applyPullResponse(_ response: SyncPullResponse, context: ModelContext) throws {
        if let notes = response.notes {
            for item in notes {
                guard item.deletedAt == nil else { continue }
                guard let id = UUID(uuidString: item.clientId) else { continue }
                let updatedAt = isoFormatter.date(from: item.updatedAt) ?? Date()

                if let existing = try context.fetch(
                    FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
                ).first {
                    if existing.updatedAt <= updatedAt {
                        existing.title = item.title
                        existing.markdown = item.markdown
                        existing.folderRaw = item.folderRaw
                        existing.driveFileID = item.driveFileId
                        existing.updatedAt = updatedAt
                    }
                } else {
                    context.insert(
                        NoteRecord(
                            id: id,
                            title: item.title,
                            markdown: item.markdown,
                            folderRaw: item.folderRaw,
                            updatedAt: updatedAt,
                            driveFileID: item.driveFileId
                        )
                    )
                }
            }
        }

        if let bills = response.bills {
            for item in bills {
                guard item.deletedAt == nil else { continue }
                guard let id = UUID(uuidString: item.clientId) else { continue }
                let nextDueDate = isoFormatter.date(from: item.nextDueDate) ?? Date()

                if let existing = try context.fetch(
                    FetchDescriptor<BillRecord>(predicate: #Predicate { $0.id == id })
                ).first {
                    existing.name = item.name
                    existing.amount = item.amount
                    existing.currencyCode = item.currencyCode ?? BillCurrency.aud.rawValue
                    existing.categoryRaw = item.categoryRaw
                    existing.recurrenceRaw = item.recurrenceRaw
                    existing.customIntervalDays = item.customIntervalDays
                    existing.dueDayOfMonth = item.dueDayOfMonth
                    existing.nextDueDate = nextDueDate
                    existing.iconName = item.iconName
                    existing.notes = item.notes
                    existing.isArchived = item.isArchived
                    existing.sortOrder = item.sortOrder
                } else {
                    context.insert(
                        BillRecord(
                            id: id,
                            name: item.name,
                            amount: item.amount,
                            currencyCode: item.currencyCode ?? BillCurrency.aud.rawValue,
                            categoryRaw: item.categoryRaw,
                            recurrenceRaw: item.recurrenceRaw,
                            customIntervalDays: item.customIntervalDays,
                            dueDayOfMonth: item.dueDayOfMonth,
                            nextDueDate: nextDueDate,
                            iconName: item.iconName,
                            notes: item.notes,
                            isArchived: item.isArchived,
                            sortOrder: item.sortOrder
                        )
                    )
                }
            }
        }

        if let payments = response.billPayments {
            for item in payments {
                guard item.deletedAt == nil else { continue }
                guard let id = UUID(uuidString: item.clientId),
                      let billID = UUID(uuidString: item.billClientId) else { continue }
                let paidAt = isoFormatter.date(from: item.paidAt) ?? Date()

                if try context.fetch(
                    FetchDescriptor<BillPaymentRecord>(predicate: #Predicate { $0.id == id })
                ).isEmpty {
                    context.insert(
                        BillPaymentRecord(
                            id: id,
                            billID: billID,
                            amount: item.amount,
                            paidAt: paidAt,
                            note: item.note
                        )
                    )
                }
            }
        }

        if let settings = response.settings {
            let updatedAt = isoFormatter.date(from: settings.updatedAt) ?? Date()
            if let existing = try context.fetch(FetchDescriptor<SyncedSettingsRecord>()).first {
                if existing.updatedAt <= updatedAt {
                    try existing.apply(settings.payload)
                }
            } else {
                context.insert(try SyncedSettingsRecord(configuration: settings.payload))
            }
        }

        if let dashboard = response.dashboard {
            let updatedAt = isoFormatter.date(from: dashboard.updatedAt) ?? Date()
            if let existing = try context.fetch(FetchDescriptor<DashboardAnalysisRecord>()).first {
                if existing.updatedAt <= updatedAt {
                    try existing.apply(dashboard.payload)
                }
            } else {
                context.insert(try DashboardAnalysisRecord(stored: dashboard.payload))
            }
        }

        try context.save()
    }
}
