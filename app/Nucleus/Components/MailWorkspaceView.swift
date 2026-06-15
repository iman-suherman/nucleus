import AccountKit
import NucleusKit
import SwiftUI
import WebKit

extension Notification.Name {
    static let gmailWebSessionDidSignIn = Notification.Name("GmailWebSessionDidSignIn")
    static let gmailWebUnreadCountDidChange = Notification.Name("GmailWebUnreadCountDidChange")
    static let gmailWebUnreadPollNow = Notification.Name("GmailWebUnreadPollNow")
}

struct GmailWebView: NSViewRepresentable {
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
        loadSignIn(into: webView, email: accountEmail)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.accountEmail != accountEmail else { return }
        context.coordinator.accountEmail = accountEmail
        context.coordinator.hasReachedInbox = false
        loadSignIn(into: webView, email: accountEmail)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func signInURL(for email: String) -> URL? {
        let continueTarget =
            "https://mail.google.com/mail/u/?authuser=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)"
        var components = URLComponents(string: "https://accounts.google.com/v3/signin/identifier")
        components?.queryItems = [
            URLQueryItem(name: "service", value: "mail"),
            URLQueryItem(name: "continue", value: continueTarget),
            URLQueryItem(name: "Email", value: email),
            URLQueryItem(name: "flowName", value: "GlifWebSignIn"),
            URLQueryItem(name: "flowEntry", value: "ServiceLogin"),
        ]
        return components?.url
    }

    private func loadSignIn(into webView: WKWebView, email: String) {
        if let url = Self.signInURL(for: email) {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var accountID: UUID?
        var accountEmail: String?
        var hasReachedInbox = false
        private var unreadPollTimer: Timer?
        private var pollNowObserver: NSObjectProtocol?

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

            if path.contains("mail.google.com/mail") {
                if !hasReachedInbox, let accountID {
                    NotificationCenter.default.post(
                        name: .gmailWebSessionDidSignIn,
                        object: accountID
                    )
                }
                hasReachedInbox = true
                startUnreadPolling(in: webView)
                return
            }

            stopUnreadPolling()

            if hasReachedInbox { return }

            let isMarketingLanding =
                path.contains("workspace.google.com/gmail")
                || path.contains("google.com/gmail/about")
                || path.contains("google.com/intl/")
                || (path.contains("google.com") && !path.contains("accounts.google.com") && !path.contains("mail.google.com"))

            if isMarketingLanding, let signInURL = GmailWebView.signInURL(for: email) {
                webView.load(URLRequest(url: signInURL))
            }
        }

        private func startUnreadPolling(in webView: WKWebView) {
            stopUnreadPolling()
            reportUnreadCount(from: webView)
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self, weak webView] _ in
                guard let webView else { return }
                self?.reportUnreadCount(from: webView)
            }
            RunLoop.main.add(timer, forMode: .common)
            unreadPollTimer = timer

            pollNowObserver = NotificationCenter.default.addObserver(
                forName: .gmailWebUnreadPollNow,
                object: nil,
                queue: .main
            ) { [weak self, weak webView] _ in
                guard let webView else { return }
                self?.reportUnreadCount(from: webView)
            }
        }

        private func stopUnreadPolling() {
            unreadPollTimer?.invalidate()
            unreadPollTimer = nil
            if let pollNowObserver {
                NotificationCenter.default.removeObserver(pollNowObserver)
                self.pollNowObserver = nil
            }
        }

        private func reportUnreadCount(from webView: WKWebView) {
            guard let accountID else { return }
            webView.evaluateJavaScript(GmailWebView.unreadCountScript) { result, _ in
                let count: Int
                if let value = result as? Int {
                    count = value
                } else if let value = result as? NSNumber {
                    count = value.intValue
                } else {
                    count = 0
                }

                NotificationCenter.default.post(
                    name: .gmailWebUnreadCountDidChange,
                    object: nil,
                    userInfo: NotificationUserInfo.mailUnreadPayload(accountID: accountID, count: count)
                )
            }
        }
    }
}

private extension GmailWebView {
    static let unreadCountScript = """
    (function() {
      const titleMatch = document.title.match(/\\((\\d+)\\)/);
      if (titleMatch) return parseInt(titleMatch[1], 10);

      const selectors = [
        'a[href*="#inbox"]',
        'a[href*="inbox"]',
        '[data-tooltip*="Inbox"]',
        '[aria-label*="Inbox"]',
        '[aria-label*="inbox"]'
      ];

      for (const selector of selectors) {
        for (const link of document.querySelectorAll(selector)) {
          const label = link.getAttribute('aria-label')
            || link.getAttribute('data-tooltip')
            || link.getAttribute('title')
            || '';
          let match = label.match(/(\\d+)\\s+unread/i);
          if (match) return parseInt(match[1], 10);
          match = label.match(/inbox[,\\s]+(\\d+)/i);
          if (match) return parseInt(match[1], 10);
          match = label.match(/inbox[^\\d]*(\\d+)/i);
          if (match) return parseInt(match[1], 10);

          for (const badge of link.querySelectorAll('span, div')) {
            const text = (badge.textContent || '').trim();
            if (/^\\d+$/.test(text)) return parseInt(text, 10);
          }
        }
      }

      for (const node of document.querySelectorAll('[aria-label]')) {
        const label = node.getAttribute('aria-label') || '';
        const match = label.match(/(\\d+)\\s+unread/i);
        if (match) return parseInt(match[1], 10);
      }

      return 0;
    })();
    """
}

struct GmailUnreadPoller: View {
    let accountID: UUID
    let accountEmail: String

    var body: some View {
        GmailWebView(accountID: accountID, accountEmail: accountEmail)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }
}

struct MailWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var renamingAccount: GoogleAccount?
    @State private var renameDraft = ""
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryEmail = ""

    var body: some View {
        VStack(spacing: 0) {
            accountTabs
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if let account = selectedAccount {
                GmailWebView(accountID: account.id, accountEmail: account.email)
                    .id(account.id)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ContentUnavailableView(
                    "No Gmail account selected",
                    systemImage: "tray",
                    description: Text("Add a category and sign in with Google to begin.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $renamingAccount) { account in
            AccountCategoryEditorSheet(
                title: "Rename Category",
                actionLabel: "Save",
                categoryName: $renameDraft,
                onSubmit: {
                    viewModel.updateAccountCategory(account, name: renameDraft)
                    renamingAccount = nil
                },
                onCancel: { renamingAccount = nil }
            )
        }
        .sheet(isPresented: $isAddingCategory) {
            AddWebGmailAccountSheet(
                email: $newCategoryEmail,
                categoryName: $newCategoryName,
                onSubmit: {
                    isAddingCategory = false
                    viewModel.addWebGmailAccount(email: newCategoryEmail, categoryName: newCategoryName)
                },
                onCancel: { isAddingCategory = false }
            )
        }
    }

    private var selectedAccount: GoogleAccount? {
        if let id = settings.selectedMailAccountID {
            return viewModel.accounts.first(where: { $0.id == id })
        }
        return viewModel.accounts.first(where: { $0.isPrimary }) ?? viewModel.accounts.first
    }

    private var accountTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.accounts) { account in
                    Button {
                        settings.selectedMailAccountID = account.id
                    } label: {
                        HStack(spacing: 8) {
                            Text(account.displayName)
                                .font(.subheadline.weight(.semibold))
                            if let unread = viewModel.unreadByAccount[account.id], unread > 0 {
                                Text("\(unread)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.85), in: Capsule())
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
                    .contextMenu {
                        Button("Rename Category…") {
                            renameDraft = account.displayName
                            renamingAccount = account
                        }
                        Button("Remove Category", role: .destructive) {
                            viewModel.removeAccount(account)
                        }
                    }
                }

                Button {
                    newCategoryName = ""
                    newCategoryEmail = ""
                    isAddingCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(GoogleOAuthCoordinator.shared.isAuthenticating)
            }
        }
    }
}
