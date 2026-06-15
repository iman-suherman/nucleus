import NucleusKit
import SwiftUI
import WebKit

struct CalendarWebView: NSViewRepresentable {
    let accountID: UUID
    let accountEmail: String
    var isVisible: Bool = true

    func makeNSView(context: Context) -> EmbeddedWebViewContainer {
        let container = EmbeddedWebViewContainer()
        let webView = EmbeddedWebViewRegistry.webView(accountID: accountID, surface: .calendar)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.accountEmail = accountEmail
        container.embed(webView)
        applyVisibility(to: container)
        if !EmbeddedWebViewRegistry.hasLoadedContent(webView) {
            loadCalendar(into: webView, email: accountEmail)
        }
        return container
    }

    func updateNSView(_ container: EmbeddedWebViewContainer, context: Context) {
        context.coordinator.accountEmail = accountEmail
        applyVisibility(to: container)
    }

    private func applyVisibility(to container: EmbeddedWebViewContainer) {
        if isVisible {
            EmbeddedWebViewRegistry.hideSurfaceWebViews(.calendar, except: accountID)
            container.setEmbeddedVisibility(true)
        } else {
            container.setEmbeddedVisibility(false)
        }
    }

    static func dismantleNSView(_ container: EmbeddedWebViewContainer, coordinator: Coordinator) {
        container.setEmbeddedVisibility(false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func calendarURL(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://calendar.google.com/calendar/u/0/r/week?authuser=\(encoded)")
    }

    private static func signInURL(for email: String) -> URL? {
        guard let continueTarget = calendarURL(for: email) else { return nil }
        return GoogleWebSignInURL.signInURL(email: email, continue: continueTarget, service: .calendar)
    }

    private func loadCalendar(into webView: WKWebView, email: String) {
        if let url = Self.calendarURL(for: email) {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var accountEmail: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated,
               ExternalLinkPolicy.shouldOpenExternally(url: url) {
                ChromeLauncher.open(url: url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let email = accountEmail, let url = webView.url else { return }
            let path = url.absoluteString

            if path.contains("calendar.google.com/calendar") {
                return
            }

            let isMarketingLanding =
                path.contains("workspace.google.com/products/calendar")
                || path.contains("google.com/calendar/about")
                || (path.contains("google.com") && !path.contains("accounts.google.com") && !path.contains("calendar.google.com"))

            if isMarketingLanding, let signInURL = CalendarWebView.signInURL(for: email) {
                webView.load(URLRequest(url: signInURL))
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if EmbeddedWebViewRegistry.hasLoadedContent(webView) {
                webView.reload()
                return
            }
            guard let email = accountEmail else { return }
            if let url = CalendarWebView.calendarURL(for: email) {
                webView.load(URLRequest(url: url))
            }
        }
    }
}

struct CalendarWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings
    var isVisible: Bool = true

    var body: some View {
        Group {
            if isVisible {
                calendarContent
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calendarContent: some View {
        VStack(spacing: 0) {
            accountTabs
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)

            if let account = selectedAccount {
                if account.authMode == .webSession {
                    CalendarWebView(
                        accountID: account.id,
                        accountEmail: account.email,
                        isVisible: isVisible
                    )
                    .id("calendar-\(account.id)")
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ContentUnavailableView(
                        "Calendar preview unavailable",
                        systemImage: "calendar",
                        description: Text("Use Gmail (Web Sign-In) to view Google Calendar inside Nucleus.")
                    )
                }
            } else {
                ContentUnavailableView(
                    "No calendar account selected",
                    systemImage: "calendar",
                    description: Text("Add a Google account to view your calendar.")
                )
            }
        }
    }

    private var selectedAccount: GoogleAccount? {
        if let id = settings.selectedCalendarAccountID {
            return viewModel.accounts.first(where: { $0.id == id })
        }
        return viewModel.accounts.first(where: { $0.isPrimary }) ?? viewModel.accounts.first
    }

    private var accountTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.accounts) { account in
                    Button {
                        settings.selectedCalendarAccountID = account.id
                    } label: {
                        Text(account.displayName)
                            .font(.subheadline.weight(.semibold))
                            .nucleusAccountTab(isSelected: selectedAccount?.id == account.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
