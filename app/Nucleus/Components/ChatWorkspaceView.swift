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
    var isVisible: Bool = true

    func makeNSView(context: Context) -> EmbeddedWebViewContainer {
        let container = EmbeddedWebViewContainer()
        let webView = EmbeddedWebViewRegistry.webView(accountID: accountID, surface: .chat)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.accountID = accountID
        context.coordinator.accountEmail = accountEmail
        container.embed(webView)
        applyVisibility(to: container)
        if !EmbeddedWebViewRegistry.hasLoadedContent(webView) {
            loadChat(into: webView, email: accountEmail)
        } else {
            context.coordinator.resumeUnreadPollingIfNeeded(in: webView)
        }
        return container
    }

    func updateNSView(_ container: EmbeddedWebViewContainer, context: Context) {
        context.coordinator.accountID = accountID
        context.coordinator.accountEmail = accountEmail
        applyVisibility(to: container)
        if isVisible, let webView = container.embeddedWebView {
            context.coordinator.resumeUnreadPollingIfNeeded(in: webView)
        }
    }

    private func applyVisibility(to container: EmbeddedWebViewContainer) {
        if isVisible {
            EmbeddedWebViewRegistry.hideSurfaceWebViews(.chat, except: accountID)
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

    static func pollUnreadCount(accountID: UUID) {
        guard let webView = EmbeddedWebViewRegistry.existingWebView(accountID: accountID, surface: .chat),
              webView.url?.absoluteString.contains("chat") == true else { return }

        webView.evaluateJavaScript(unreadCountScript) { result, _ in
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
                userInfo: NotificationUserInfo.mailUnreadPayload(accountID: accountID, count: count)
            )
        }
    }

    static func chatURL(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://mail.google.com/chat/u/0/?authuser=\(encoded)")
    }

    private static func signInURL(for email: String) -> URL? {
        guard let continueTarget = chatURL(for: email) else { return nil }
        return GoogleWebSignInURL.signInURL(email: email, continue: continueTarget, service: .chat)
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

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if EmbeddedWebViewRegistry.hasLoadedContent(webView) {
                webView.reload()
                return
            }
            guard let email = accountEmail else { return }
            if let url = ChatWebView.chatURL(for: email) {
                webView.load(URLRequest(url: url))
            }
        }

        func resumeUnreadPollingIfNeeded(in webView: WKWebView) {
            guard webView.url?.absoluteString.contains("mail.google.com/chat") == true
                || webView.url?.absoluteString.contains("chat.google.com") == true else { return }
            startUnreadPolling(in: webView)
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
                    userInfo: NotificationUserInfo.mailUnreadPayload(accountID: accountID, count: count)
                )
            }
        }
    }
}

struct ChatUnreadPoller: View {
    let accountID: UUID

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                ChatWebView.pollUnreadCount(accountID: accountID)
            }
    }
}

private extension ChatWebView {
    static let unreadCountScript = """
    (function() {
      const titleMatch = document.title.match(/\\((\\d+)\\)/);
      if (titleMatch) return parseInt(titleMatch[1], 10);

      let total = 0;
      const selectors = [
        '[aria-label*="unread"]',
        '[data-tooltip*="unread"]',
        'a[href*="/chat/"]',
        'a[href*="chat.google.com"]'
      ];

      for (const selector of selectors) {
        for (const node of document.querySelectorAll(selector)) {
          const label = node.getAttribute('aria-label')
            || node.getAttribute('data-tooltip')
            || node.getAttribute('title')
            || '';
          const match = label.match(/(\\d+)\\s+unread/i);
          if (match) {
            total += parseInt(match[1], 10);
            continue;
          }
          if (/unread message/i.test(label) && !/0 unread/i.test(label)) {
            total += 1;
          }
        }
      }

      if (total > 0) return total;

      for (const node of document.querySelectorAll('[aria-label]')) {
        const label = node.getAttribute('aria-label') || '';
        const match = label.match(/(\\d+)\\s+unread/i);
        if (match) total += parseInt(match[1], 10);
      }

      return total;
    })();
    """
}

struct ChatWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings
    var isVisible: Bool = true

    var body: some View {
        Group {
            if isVisible {
                chatContent
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            accountTabs
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if let account = selectedAccount {
                ChatWebView(
                    accountID: account.id,
                    accountEmail: account.email,
                    isVisible: isVisible
                )
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
                                NucleusCountBadge(count: unread, kind: .chat)
                            }
                        }
                        .nucleusAccountTab(isSelected: selectedAccount?.id == account.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
