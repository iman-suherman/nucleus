import Foundation
import WebKit

@MainActor
enum GmailWebSessionStore {
    static func dataStore(for accountID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: accountID)
    }

    static func cookies(for accountID: UUID) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore(for: accountID).httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    static func clear(for accountID: UUID) async {
        try? await WKWebsiteDataStore.remove(forIdentifier: accountID)
    }
}
