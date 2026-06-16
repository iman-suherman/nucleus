import DatabaseKit
import Foundation
import NucleusKit
import SwiftData

@MainActor
public final class MobileAccountService: ObservableObject {
    @Published public private(set) var accounts: [GoogleAccount] = []

    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        reload()
    }

    public func reload() {
        let context = ModelContext(modelContainer)
        accounts = (try? AccountRepository.fetchAll(context: context)) ?? []
    }

    public func addAccount(email: String, displayName: String) throws -> GoogleAccount {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else {
            throw AccountServiceError.invalidEmail
        }

        let account = GoogleAccount(
            email: trimmedEmail,
            displayName: displayName.isEmpty ? trimmedEmail : displayName,
            isPrimary: accounts.isEmpty,
            isPrimaryNotesAccount: accounts.isEmpty,
            authMode: .webSession
        )

        let context = ModelContext(modelContainer)
        try AccountRepository.upsert(account, context: context)
        reload()
        return account
    }

    public func removeAccount(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        try AccountRepository.delete(id: id, context: context)
        await WebSessionStore.clear(for: id)
        WebViewRegistry.remove(accountID: id)
        reload()
    }

    public func setPrimary(id: UUID) throws {
        let context = ModelContext(modelContainer)
        try AccountRepository.setPrimary(id: id, context: context)
        reload()
    }

    public func primaryAccount() -> GoogleAccount? {
        accounts.first(where: { $0.isPrimary }) ?? accounts.first
    }

    public func account(for surface: WebSurface, preferences: MobilePreferences) -> GoogleAccount? {
        let selectedID: String?
        switch surface {
        case .mail:
            selectedID = preferences.selectedMailAccountID
        case .calendar:
            selectedID = preferences.selectedCalendarAccountID
        case .chat:
            selectedID = preferences.selectedChatAccountID
        }

        if let selectedID, let uuid = UUID(uuidString: selectedID),
           let match = accounts.first(where: { $0.id == uuid }) {
            return match
        }
        return primaryAccount()
    }
}

public enum AccountServiceError: Error, LocalizedError {
    case invalidEmail

    public var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter a valid Gmail address."
        }
    }
}
