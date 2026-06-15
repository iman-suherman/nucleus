import Foundation
import WebKit

@MainActor
enum EmbeddedWebViewRegistry {
    enum Surface: Hashable {
        case mail
        case chat
        case calendar
    }

    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private struct CacheKey: Hashable {
        let accountID: UUID
        let surface: Surface
    }

    private static var webViews: [CacheKey: WKWebView] = [:]

    static func webView(accountID: UUID, surface: Surface) -> WKWebView {
        let key = CacheKey(accountID: accountID, surface: surface)
        if let existing = webViews[key] {
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = GmailWebSessionStore.dataStore(for: accountID)
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = safariUserAgent
        webViews[key] = webView
        return webView
    }

    static func existingWebView(accountID: UUID, surface: Surface) -> WKWebView? {
        webViews[CacheKey(accountID: accountID, surface: surface)]
    }

    static func hasLoadedContent(_ webView: WKWebView) -> Bool {
        guard let url = webView.url else { return false }
        let path = url.absoluteString
        return !path.isEmpty && path != "about:blank"
    }

    static func remove(accountID: UUID) {
        for surface in [Surface.mail, .chat, .calendar] {
            let key = CacheKey(accountID: accountID, surface: surface)
            webViews.removeValue(forKey: key)?.stopLoading()
        }
    }
}
