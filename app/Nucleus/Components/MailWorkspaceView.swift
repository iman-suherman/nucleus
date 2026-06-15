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
    var isActive: Bool = true

    func makeNSView(context: Context) -> WKWebView {
        let webView = EmbeddedWebViewRegistry.webView(accountID: accountID, surface: .mail)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.accountID = accountID
        context.coordinator.accountEmail = accountEmail
        if !EmbeddedWebViewRegistry.hasLoadedContent(webView) {
            loadInbox(into: webView, email: accountEmail)
        } else if isActive {
            context.coordinator.resumeUnreadPollingIfNeeded(in: webView)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.accountID = accountID
        context.coordinator.accountEmail = accountEmail

        if isActive {
            context.coordinator.resumeUnreadPollingIfNeeded(in: webView)
        } else {
            context.coordinator.stopUnreadPolling()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func pollUnreadCount(accountID: UUID) {
        guard let webView = EmbeddedWebViewRegistry.existingWebView(accountID: accountID, surface: .mail),
              webView.window != nil,
              webView.url?.absoluteString.contains("mail.google.com/mail") == true else { return }

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
                name: .gmailWebUnreadCountDidChange,
                object: nil,
                userInfo: NotificationUserInfo.mailUnreadPayload(accountID: accountID, count: count)
            )
        }
    }

    static func inboxURL(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://mail.google.com/mail/u/?authuser=\(encoded)")
    }

    private static func signInURL(for email: String) -> URL? {
        guard let continueTarget = inboxURL(for: email)?.absoluteString else { return nil }
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

    private func loadInbox(into webView: WKWebView, email: String) {
        if let url = Self.inboxURL(for: email) {
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
            stopUnreadPolling()
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

            let needsSignIn =
                path.contains("accounts.google.com")
                || path.contains("workspace.google.com/gmail")
                || path.contains("google.com/gmail/about")
                || path.contains("google.com/intl/")

            if needsSignIn, let signInURL = GmailWebView.signInURL(for: email) {
                webView.load(URLRequest(url: signInURL))
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if EmbeddedWebViewRegistry.hasLoadedContent(webView) {
                webView.reload()
                return
            }
            guard let email = accountEmail else { return }
            if let url = GmailWebView.inboxURL(for: email) {
                webView.load(URLRequest(url: url))
            }
        }

        func resumeUnreadPollingIfNeeded(in webView: WKWebView) {
            guard webView.url?.absoluteString.contains("mail.google.com/mail") == true else { return }
            hasReachedInbox = true
            startUnreadPolling(in: webView)
        }

        private func startUnreadPolling(in webView: WKWebView) {
            stopUnreadPolling()
            reportUnreadCount(from: webView)
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self, weak webView] _ in
                guard let webView, webView.window != nil else { return }
                self?.reportUnreadCount(from: webView)
            }
            RunLoop.main.add(timer, forMode: .common)
            unreadPollTimer = timer

            pollNowObserver = NotificationCenter.default.addObserver(
                forName: .gmailWebUnreadPollNow,
                object: nil,
                queue: .main
            ) { [weak self, weak webView] _ in
                guard let webView, webView.window != nil else { return }
                self?.reportUnreadCount(from: webView)
            }
        }

        func stopUnreadPolling() {
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

      return 0;
    })();
    """
}

struct GmailUnreadPoller: View {
    let accountID: UUID

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                GmailWebView.pollUnreadCount(accountID: accountID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .gmailWebUnreadPollNow)) { _ in
                GmailWebView.pollUnreadCount(accountID: accountID)
            }
    }
}

struct MailWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings
    var isActive: Bool = true

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

            if viewModel.accounts.isEmpty {
                ContentUnavailableView(
                    "No Gmail account selected",
                    systemImage: "tray",
                    description: Text("Add a category and sign in with Google to begin.")
                )
            } else if isActive, let account = selectedAccount {
                GmailWebView(
                    accountID: account.id,
                    accountEmail: account.email,
                    isActive: true
                )
                .id(account.id)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                Color.clear
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
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
                                NucleusCountBadge(count: unread, kind: .mail)
                            }
                        }
                        .nucleusAccountTab(isSelected: selectedAccount?.id == account.id)
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
                        .nucleusAccountTab(isSelected: false)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
