import AccountKit
import NucleusKit
import SwiftUI
import WebKit

extension Notification.Name {
    static let chatWebUnreadCountDidChange = Notification.Name("ChatWebUnreadCountDidChange")
}

struct ChatWebView: NSViewRepresentable {
    let accountID: UUID
    let accountEmail: String

    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = GmailWebSessionStore.dataStore(for: accountID)
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = Self.safariUserAgent
        context.coordinator.accountID = accountID
        context.coordinator.accountEmail = accountEmail
        loadChat(into: webView, email: accountEmail)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.accountEmail != accountEmail else { return }
        context.coordinator.accountID = accountID
        context.coordinator.accountEmail = accountEmail
        loadChat(into: webView, email: accountEmail)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func chatURL(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://mail.google.com/chat/u/0/?authuser=\(encoded)")
    }

    private static func signInURL(for email: String) -> URL? {
        guard let continueTarget = chatURL(for: email)?.absoluteString else { return nil }
        var components = URLComponents(string: "https://accounts.google.com/v3/signin/identifier")
        components?.queryItems = [
            URLQueryItem(name: "service", value: "chat"),
            URLQueryItem(name: "continue", value: continueTarget),
            URLQueryItem(name: "Email", value: email),
            URLQueryItem(name: "flowName", value: "GlifWebSignIn"),
            URLQueryItem(name: "flowEntry", value: "ServiceLogin"),
        ]
        return components?.url
    }

    private func loadChat(into webView: WKWebView, email: String) {
        if let url = Self.chatURL(for: email) {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var accountID: UUID?
        var accountEmail: String?
        private var unreadPollTimer: Timer?

        deinit {
            unreadPollTimer?.invalidate()
        }

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

            if path.contains("mail.google.com/chat") || path.contains("chat.google.com") {
                startUnreadPolling(in: webView)
                return
            }

            stopUnreadPolling()

            let needsSignIn =
                path.contains("accounts.google.com")
                || path.contains("workspace.google.com")
                || path.contains("google.com/chat/about")

            if needsSignIn, let signInURL = ChatWebView.signInURL(for: email) {
                webView.load(URLRequest(url: signInURL))
            }
        }

        private func startUnreadPolling(in webView: WKWebView) {
            stopUnreadPolling()
            reportUnreadCount(from: webView)
            unreadPollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self, weak webView] _ in
                guard let webView else { return }
                self?.reportUnreadCount(from: webView)
            }
        }

        private func stopUnreadPolling() {
            unreadPollTimer?.invalidate()
            unreadPollTimer = nil
        }

        private func reportUnreadCount(from webView: WKWebView) {
            guard let accountID else { return }
            webView.evaluateJavaScript(ChatWebView.unreadCountScript) { result, _ in
                let count: Int
                if let value = result as? Int {
                    count = value
                } else if let value = result as? NSNumber {
                    count = value.intValue
                } else {
                    count = 0
                }

                NotificationCenter.default.post(
                    name: .chatWebUnreadCountDidChange,
                    object: nil,
                    userInfo: [
                        "accountID": accountID,
                        "count": count,
                    ]
                )
            }
        }
    }
}

struct ChatUnreadPoller: View {
    let accountID: UUID
    let accountEmail: String

    var body: some View {
        ChatWebView(accountID: accountID, accountEmail: accountEmail)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }
}

private extension ChatWebView {
    static let unreadCountScript = """
    (function() {
      const titleMatch = document.title.match(/\\((\\d+)\\)/);
      if (titleMatch) return parseInt(titleMatch[1], 10);
      let count = 0;
      document.querySelectorAll('[aria-label]').forEach(function(node) {
        const label = node.getAttribute('aria-label') || '';
        const match = label.match(/(\\d+)\\s+unread/i);
        if (match) count += parseInt(match[1], 10);
        else if (/unread message/i.test(label)) count += 1;
      });
      return count;
    })();
    """
}

struct ChatWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            accountTabs
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if let account = selectedAccount {
                ChatWebView(accountID: account.id, accountEmail: account.email)
                    .id(account.id)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ContentUnavailableView(
                    "No chat account selected",
                    systemImage: "message",
                    description: Text("Add a Google account and sign in to use Google Chat.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedAccount: GoogleAccount? {
        if let id = settings.selectedChatAccountID {
            return viewModel.accounts.first(where: { $0.id == id })
        }
        return viewModel.accounts.first(where: { $0.isPrimary }) ?? viewModel.accounts.first
    }

    private var accountTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.accounts) { account in
                    Button {
                        settings.selectedChatAccountID = account.id
                    } label: {
                        HStack(spacing: 8) {
                            Text(account.displayName)
                                .font(.subheadline.weight(.semibold))
                            if let unread = viewModel.chatUnreadByAccount[account.id], unread > 0 {
                                Text("\(unread)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.85), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedAccount?.id == account.id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
