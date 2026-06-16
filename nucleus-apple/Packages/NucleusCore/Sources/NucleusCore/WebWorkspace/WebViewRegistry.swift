import Foundation
import WebKit

@MainActor
public enum WebViewRegistry {
    private struct CacheKey: Hashable {
        let accountID: UUID
        let surface: WebSurface
    }

    private static let sharedProcessPool = WKProcessPool()
    private static var webViews: [CacheKey: WKWebView] = [:]

    public static var defaultUserAgent: String {
        #if os(iOS)
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        #else
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        #endif
    }

    public static func webView(accountID: UUID, surface: WebSurface) -> WKWebView {
        let key = CacheKey(accountID: accountID, surface: surface)
        if let existing = webViews[key] {
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.processPool = sharedProcessPool
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = WebSessionStore.dataStore(for: accountID)
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = defaultUserAgent
        webViews[key] = webView
        return webView
    }

    public static func existingWebView(accountID: UUID, surface: WebSurface) -> WKWebView? {
        webViews[CacheKey(accountID: accountID, surface: surface)]
    }

    public static func hasLoadedContent(_ webView: WKWebView) -> Bool {
        guard let url = webView.url else { return false }
        let path = url.absoluteString
        return !path.isEmpty && path != "about:blank"
    }

    public static func remove(accountID: UUID) {
        for surface in WebSurface.allCases {
            let key = CacheKey(accountID: accountID, surface: surface)
            webViews.removeValue(forKey: key)?.stopLoading()
        }
    }

    public static func hideSurfaceWebViews(_ surface: WebSurface, except accountID: UUID? = nil) {
        for (key, webView) in webViews where key.surface == surface && key.accountID != accountID {
            setWebViewHidden(webView, hidden: true)
        }
    }

    private static func setWebViewHidden(_ webView: WKWebView, hidden: Bool) {
        #if os(iOS)
        webView.isHidden = hidden
        webView.alpha = hidden ? 0 : 1
        #else
        webView.isHidden = hidden
        webView.alphaValue = hidden ? 0 : 1
        #endif
    }
}
