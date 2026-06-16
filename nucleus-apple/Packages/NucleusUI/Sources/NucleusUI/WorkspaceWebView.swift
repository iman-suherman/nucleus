import NucleusCore
import SwiftUI
import WebKit

#if canImport(UIKit)
import UIKit
#endif

public struct WorkspaceWebView: UIViewRepresentable {
    let accountID: UUID
    let accountEmail: String
    let surface: WebSurface
    var isVisible: Bool = true
    var preferSignIn: Bool = false
    var onSignedIn: (() -> Void)?

    public init(
        accountID: UUID,
        accountEmail: String,
        surface: WebSurface,
        isVisible: Bool = true,
        preferSignIn: Bool = false,
        onSignedIn: (() -> Void)? = nil
    ) {
        self.accountID = accountID
        self.accountEmail = accountEmail
        self.surface = surface
        self.isVisible = isVisible
        self.preferSignIn = preferSignIn
        self.onSignedIn = onSignedIn
    }

    public func makeUIView(context: Context) -> WKWebView {
        let webView = WebViewRegistry.webView(accountID: accountID, surface: surface)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isHidden = !isVisible
        webView.alpha = isVisible ? 1 : 0

        if !WebViewRegistry.hasLoadedContent(webView),
           let url = WebWorkspaceURLs.initialURL(for: surface, email: accountEmail, preferSignIn: preferSignIn) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSignedIn = onSignedIn
        webView.isHidden = !isVisible
        webView.alpha = isVisible ? 1 : 0

        if isVisible {
            WebViewRegistry.hideSurfaceWebViews(surface, except: accountID)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(accountEmail: accountEmail, surface: surface, onSignedIn: onSignedIn)
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let accountEmail: String
        let surface: WebSurface
        var onSignedIn: (() -> Void)?

        init(accountEmail: String, surface: WebSurface, onSignedIn: (() -> Void)?) {
            self.accountEmail = accountEmail
            self.surface = surface
            self.onSignedIn = onSignedIn
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated,
               ExternalLinkPolicy.shouldOpenExternally(url: url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        public func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let path = webView.url?.absoluteString ?? ""
            if GoogleWebSignInURL.isGoogleSignInPage(path) {
                webView.evaluateJavaScript(
                    GoogleWebSignInURL.prefillEmailScript(email: accountEmail),
                    completionHandler: nil
                )
            }

            if WebWorkspaceURLs.isLoadedContent(webView.url, for: surface) {
                onSignedIn?()
            }
        }
    }
}
