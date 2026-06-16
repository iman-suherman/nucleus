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
    var isVisible: Bool = true
    var preferSignIn: Bool = false
    @Binding var isLoading: Bool

    func makeNSView(context: Context) -> EmbeddedWebViewContainer {
        let container = EmbeddedWebViewContainer()
        let webView = EmbeddedWebViewRegistry.webView(accountID: accountID, surface: .mail)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.accountID = accountID
        context.coordinator.accountEmail = accountEmail
        container.embed(webView)
        applyVisibility(to: container)
        if !EmbeddedWebViewRegistry.hasLoadedContent(webView) {
            isLoading = true
            loadInbox(into: webView, email: accountEmail, preferSignIn: preferSignIn)
        } else if webView.url?.absoluteString.contains("mail.google.com/mail") == true {
            isLoading = false
            context.coordinator.resumeUnreadPollingIfNeeded(in: webView)
        } else {
            isLoading = true
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
            EmbeddedWebViewRegistry.hideMailWebViews(except: accountID)
            container.setEmbeddedVisibility(true)
        } else {
            container.setEmbeddedVisibility(false)
        }
    }

    static func dismantleNSView(_ container: EmbeddedWebViewContainer, coordinator: Coordinator) {
        container.setEmbeddedVisibility(false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    static func navigateToInbox(accountID: UUID, email: String, isLoading: Binding<Bool>? = nil) {
        guard let webView = EmbeddedWebViewRegistry.existingWebView(accountID: accountID, surface: .mail),
              let url = inboxURL(for: email) else { return }
        isLoading?.wrappedValue = true
        webView.load(URLRequest(url: url))
    }

    static func ensureUnreadSync(accountID: UUID, email: String) {
        let webView = EmbeddedWebViewRegistry.webView(accountID: accountID, surface: .mail)
        if !EmbeddedWebViewRegistry.hasLoadedContent(webView),
           let url = inboxURL(for: email) {
            webView.load(URLRequest(url: url))
        }
        pollUnreadCount(accountID: accountID)
    }

    static func pollUnreadCount(accountID: UUID) {
        guard let webView = EmbeddedWebViewRegistry.existingWebView(accountID: accountID, surface: .mail),
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
        guard let continueTarget = inboxURL(for: email) else { return nil }
        return GoogleWebSignInURL.signInURL(email: email, continue: continueTarget, service: .mail)
    }

    private func loadInbox(into webView: WKWebView, email: String, preferSignIn: Bool = false) {
        if preferSignIn, let url = Self.signInURL(for: email) {
            webView.load(URLRequest(url: url))
            return
        }
        if let url = Self.inboxURL(for: email) {
            webView.load(URLRequest(url: url))
        }
    }

    private static func prefillSignInEmail(in webView: WKWebView, email: String) {
        webView.evaluateJavaScript(GoogleWebSignInURL.prefillEmailScript(email: email), completionHandler: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var isLoading: Binding<Bool>
        var accountID: UUID?
        var accountEmail: String?
        var hasReachedInbox = false
        private var unreadPollTimer: Timer?
        private var pollNowObserver: NSObjectProtocol?

        init(isLoading: Binding<Bool>) {
            self.isLoading = isLoading
        }

        deinit {
            stopUnreadPolling()
        }

        private func setLoading(_ loading: Bool) {
            DispatchQueue.main.async {
                self.isLoading.wrappedValue = loading
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            setLoading(true)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            setLoading(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            setLoading(false)
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
                setLoading(false)
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

            if needsSignIn {
                if path.contains("accounts.google.com") {
                    setLoading(false)
                    if path.contains("signin/identifier") {
                        GmailWebView.prefillSignInEmail(in: webView, email: email)
                    }
                    return
                }

                let pendingSignIn = accountID.map { AppViewModel.current?.isMailSignInPending($0) == true } ?? false
                let targetURL = pendingSignIn
                    ? GmailWebView.signInURL(for: email)
                    : GmailWebView.inboxURL(for: email)
                if let targetURL {
                    webView.load(URLRequest(url: targetURL))
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if EmbeddedWebViewRegistry.hasLoadedContent(webView) {
                setLoading(true)
                webView.reload()
                return
            }
            guard let email = accountEmail else { return }
            setLoading(true)
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
    let accountEmail: String

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                GmailWebView.ensureUnreadSync(accountID: accountID, email: accountEmail)
            }
            .onReceive(NotificationCenter.default.publisher(for: .gmailWebUnreadPollNow)) { _ in
                GmailWebView.ensureUnreadSync(accountID: accountID, email: accountEmail)
            }
    }
}

struct MailWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings
    var isVisible: Bool = true

    @State private var renamingAccount: GoogleAccount?
    @State private var renameDraft = ""
    @State private var isInboxLoading = true

    var body: some View {
        Group {
            if isVisible {
                mailContent
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedAccount?.id) { _, _ in
            isInboxLoading = true
        }
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
    }

    private var mailContent: some View {
        VStack(spacing: 0) {
            accountTabs
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if viewModel.accounts.isEmpty {
                ContentUnavailableView(
                    "No Gmail account selected",
                    systemImage: "tray",
                    description: Text("Add a Gmail account and sign in with Google to begin.")
                )
            } else if let account = selectedAccount {
                ZStack {
                    GmailWebView(
                        accountID: account.id,
                        accountEmail: account.email,
                        isVisible: isVisible,
                        preferSignIn: viewModel.isMailSignInPending(account.id),
                        isLoading: $isInboxLoading
                    )
                    .id(account.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isInboxLoading {
                        inboxLoadingOverlay
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                ContentUnavailableView(
                    "No Gmail account selected",
                    systemImage: "tray",
                    description: Text("Add a Gmail account and sign in with Google to begin.")
                )
            }
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
                        selectAccountTab(account)
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
                    .pointerCursor()
                    .help(mailAccountTabTooltip(for: account))
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
                    viewModel.sidebarSelection = .workspace(.accounts)
                } label: {
                    Label("Add Gmail Account", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .nucleusAccountTab(isSelected: false)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Open Accounts to add a Gmail account")
            }
        }
    }

    private var inboxLoadingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading inbox…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectAccountTab(_ account: GoogleAccount) {
        settings.selectedMailAccountID = account.id
        isInboxLoading = true
        GmailWebView.navigateToInbox(accountID: account.id, email: account.email, isLoading: $isInboxLoading)
    }

    private func mailAccountTabTooltip(for account: GoogleAccount) -> String {
        if selectedAccount?.id == account.id {
            return "Return to \(account.displayName) inbox"
        }
        return "Switch to \(account.displayName) and open the mail list"
    }
}
