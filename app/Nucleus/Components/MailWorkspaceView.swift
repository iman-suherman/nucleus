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
    @Binding var loadingPhase: MailInboxLoadingPhase

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
            loadingPhase = .connecting
            isLoading = true
            loadInbox(into: webView, email: accountEmail, preferSignIn: preferSignIn)
        } else if webView.url?.absoluteString.contains("mail.google.com/mail") == true {
            loadingPhase = .idle
            isLoading = false
            context.coordinator.hasReachedInbox = true
            context.coordinator.resumeUnreadPollingIfNeeded(in: webView)
        } else {
            loadingPhase = .connecting
            isLoading = true
            loadInbox(into: webView, email: accountEmail, preferSignIn: preferSignIn)
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
        Coordinator(isLoading: $isLoading, loadingPhase: $loadingPhase)
    }

    static func navigateToInbox(
        accountID: UUID,
        email: String,
        isLoading: Binding<Bool>? = nil,
        loadingPhase: Binding<MailInboxLoadingPhase>? = nil
    ) {
        guard let webView = EmbeddedWebViewRegistry.existingWebView(accountID: accountID, surface: .mail),
              let url = inboxURL(for: email) else { return }
        loadingPhase?.wrappedValue = .connecting
        isLoading?.wrappedValue = true
        webView.load(URLRequest(url: url))
        if webView.url?.absoluteString.contains("mail.google.com/mail") == true, !webView.isLoading {
            loadingPhase?.wrappedValue = .idle
            isLoading?.wrappedValue = false
        }
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
        var loadingPhase: Binding<MailInboxLoadingPhase>
        var accountID: UUID?
        var accountEmail: String?
        var hasReachedInbox = false
        private var unreadPollTimer: Timer?
        private var pollNowObserver: NSObjectProtocol?
        private var readyCheckGeneration = 0
        private var loadWatchdog: Timer?

        init(isLoading: Binding<Bool>, loadingPhase: Binding<MailInboxLoadingPhase>) {
            self.isLoading = isLoading
            self.loadingPhase = loadingPhase
        }

        deinit {
            stopUnreadPolling()
            loadWatchdog?.invalidate()
        }

        private func setLoading(_ loading: Bool) {
            DispatchQueue.main.async {
                if loading {
                    self.scheduleLoadWatchdog()
                } else {
                    self.loadWatchdog?.invalidate()
                    self.loadWatchdog = nil
                }
                self.isLoading.wrappedValue = loading
                if !loading {
                    self.loadingPhase.wrappedValue = .idle
                }
            }
        }

        private func setPhase(_ phase: MailInboxLoadingPhase) {
            DispatchQueue.main.async {
                self.loadingPhase.wrappedValue = phase
            }
        }

        private func isInboxURL(_ url: URL?) -> Bool {
            url?.absoluteString.lowercased().contains("mail.google.com/mail") == true
        }

        private func scheduleLoadWatchdog() {
            loadWatchdog?.invalidate()
            loadWatchdog = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.forceDismissOverlayIfStuck()
                }
            }
            if let loadWatchdog {
                RunLoop.main.add(loadWatchdog, forMode: .common)
            }
        }

        private func forceDismissOverlayIfStuck() {
            guard isLoading.wrappedValue else { return }
            guard let webView = accountID.flatMap({
                EmbeddedWebViewRegistry.existingWebView(accountID: $0, surface: .mail)
            }) else {
                setLoading(false)
                return
            }
            if isInboxURL(webView.url) {
                markInboxReached(webView, isFirstReach: !hasReachedInbox)
            }
        }

        private func markInboxReached(_ webView: WKWebView, isFirstReach: Bool) {
            let firstTime = !hasReachedInbox
            hasReachedInbox = true
            setLoading(false)

            guard firstTime else { return }

            if isFirstReach, let accountID {
                NotificationCenter.default.post(
                    name: .gmailWebSessionDidSignIn,
                    object: accountID
                )
            }
            setPhase(.renderingMailbox)
            waitForWebViewReady(webView, isFirstReach: isFirstReach)
            startUnreadPolling(in: webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard !hasReachedInbox else { return }
            setPhase(MailInboxLoadingPhase.phase(for: webView.url))
            setLoading(true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard !hasReachedInbox, isInboxURL(webView.url) else { return }
            markInboxReached(webView, isFirstReach: true)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            setPhase(.failed(error.localizedDescription))
            setLoading(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            setPhase(.failed(error.localizedDescription))
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

            if isInboxURL(url) {
                markInboxReached(webView, isFirstReach: !hasReachedInbox)
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
                    setPhase(.signingIn)
                    if path.contains("signin/identifier") {
                        GmailWebView.prefillSignInEmail(in: webView, email: email)
                    }
                    return
                }

                setPhase(.redirecting)
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
            hasReachedInbox = false
            if EmbeddedWebViewRegistry.hasLoadedContent(webView) {
                setPhase(.loadingInbox)
                setLoading(true)
                webView.reload()
                return
            }
            guard let email = accountEmail else { return }
            setPhase(.connecting)
            setLoading(true)
            if let url = GmailWebView.inboxURL(for: email) {
                webView.load(URLRequest(url: url))
            }
        }

        private func waitForWebViewReady(_ webView: WKWebView, isFirstReach: Bool) {
            readyCheckGeneration += 1
            let generation = readyCheckGeneration

            func check(attempts: Int) {
                guard generation == readyCheckGeneration else { return }

                webView.evaluateJavaScript(GmailWebView.inboxReadyScript) { result, _ in
                    guard generation == self.readyCheckGeneration else { return }

                    let domReady = (result as? Bool) == true
                    let progress = webView.estimatedProgress
                    let ready = domReady || progress >= 0.85 || attempts >= 15

                    if ready {
                        if isFirstReach {
                            self.setPhase(.syncingUnread)
                        }
                        return
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        check(attempts: attempts + 1)
                    }
                }
            }

            check(attempts: 0)
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
    static let inboxReadyScript = """
    (function() {
      if (document.readyState !== 'complete' && document.readyState !== 'interactive') return false;
      const main = document.querySelector('[role="main"]');
      if (main && main.children.length > 0) return true;
      const inboxNav = document.querySelector('a[href*="#inbox"], [aria-label*="Inbox"], [data-tooltip*="Inbox"]');
      if (inboxNav) return true;
      return document.body && document.body.children.length > 2;
    })();
    """

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
    @State private var isInboxLoading = false
    @State private var inboxLoadingPhase: MailInboxLoadingPhase = .connecting

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
            inboxLoadingPhase = .connecting
            isInboxLoading = selectedAccount != nil
        }
        .onChange(of: viewModel.accounts.isEmpty) { _, isEmpty in
            if isEmpty {
                isInboxLoading = false
                inboxLoadingPhase = .idle
            }
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
            if !viewModel.accounts.isEmpty {
                accountTabs
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }

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
                        isLoading: $isInboxLoading,
                        loadingPhase: $inboxLoadingPhase
                    )
                    .id(account.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isInboxLoading {
                        if inboxLoadingPhase == .signingIn {
                            VStack {
                                inboxLoadingBanner
                                Spacer()
                            }
                            .allowsHitTesting(false)
                        } else {
                            inboxLoadingOverlay
                        }
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
                        Button("Remove from Nucleus", role: .destructive) {
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

    private var inboxLoadingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(inboxLoadingPhase.title)
                    .font(.subheadline.weight(.semibold))
                Text(inboxLoadingPhase.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    private var inboxLoadingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inboxLoadingPhase.title)
                            .font(.headline)
                        if let step = inboxLoadingPhase.stepNumber {
                            Text("Step \(step) of \(MailInboxLoadingPhase.stepCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !inboxLoadingPhase.detail.isEmpty {
                    Text(inboxLoadingPhase.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(MailInboxLoadingPhase.orderedSteps, id: \.self) { step in
                        HStack(spacing: 8) {
                            Image(systemName: inboxStepIcon(for: step))
                                .foregroundStyle(inboxStepColor(for: step))
                                .frame(width: 16)
                            Text(step.title)
                                .font(.caption)
                                .foregroundStyle(inboxStepColor(for: step))
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 420, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inboxStepIcon(for step: MailInboxLoadingPhase) -> String {
        if step.isCompleted(relativeTo: inboxLoadingPhase) {
            return "checkmark.circle.fill"
        }
        if step.isCurrent(inboxLoadingPhase) {
            return "ellipsis.circle.fill"
        }
        return "circle"
    }

    private func inboxStepColor(for step: MailInboxLoadingPhase) -> Color {
        if step.isCompleted(relativeTo: inboxLoadingPhase) {
            return .green
        }
        if step.isCurrent(inboxLoadingPhase) {
            return .accentColor
        }
        return .secondary.opacity(0.55)
    }

    private func selectAccountTab(_ account: GoogleAccount) {
        settings.selectedMailAccountID = account.id
        inboxLoadingPhase = .connecting
        isInboxLoading = true
        GmailWebView.navigateToInbox(
            accountID: account.id,
            email: account.email,
            isLoading: $isInboxLoading,
            loadingPhase: $inboxLoadingPhase
        )
    }

    private func mailAccountTabTooltip(for account: GoogleAccount) -> String {
        if selectedAccount?.id == account.id {
            return "Return to \(account.displayName) inbox"
        }
        return "Switch to \(account.displayName) and open the mail list"
    }
}
