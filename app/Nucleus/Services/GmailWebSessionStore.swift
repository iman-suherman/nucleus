import Foundation
import WebKit

enum GmailWebSessionStore {
    static func dataStore(for accountID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: accountID)
    }

    static func clear(for accountID: UUID) {
        Task {
            try? await WKWebsiteDataStore.remove(forIdentifier: accountID)
        }
    }
}
