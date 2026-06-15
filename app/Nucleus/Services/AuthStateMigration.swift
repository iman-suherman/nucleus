import AccountKit
import DatabaseKit
import Foundation
import SwiftData

@MainActor
enum AuthStateMigration {
    private static let completedKey = "nucleus.migration.freshAuth.v1007"

    static func resetStoredLoginIfNeeded(modelContainer: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }

        let context = ModelContext(modelContainer)
        let accounts = (try? AccountRepository.fetchAll(context: context)) ?? []

        for account in accounts {
            KeychainTokenStore.shared.deleteTokens(accountID: account.id)
            try? AccountRepository.delete(id: account.id, context: context)
        }

        try? MailRepository.replaceMessages([], context: context)
        try? CalendarRepository.replaceEvents([], context: context)

        AppSettings.shared.selectedMailAccountID = nil
        AppSettings.shared.selectedCalendarAccountID = nil
        AppSettings.shared.selectedChatAccountID = nil

        UserDefaults.standard.set(true, forKey: completedKey)
    }
}
