import AccountKit
import NucleusKit
import SwiftUI
import WebKit

struct GmailWebView: NSViewRepresentable {
    let accountEmail: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedEmail != accountEmail else { return }
        context.coordinator.loadedEmail = accountEmail
        context.coordinator.hasReachedInbox = false
        loadSignIn(into: webView, email: accountEmail)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func signInURL(for email: String) -> URL? {
        let continueTarget = "https://mail.google.com/mail/u/?authuser=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)"
        var components = URLComponents(string: "https://accounts.google.com/signin/v2/identifier")
        components?.queryItems = [
            URLQueryItem(name: "service", value: "mail"),
            URLQueryItem(name: "continue", value: continueTarget),
            URLQueryItem(name: "Email", value: email),
            URLQueryItem(name: "flowName", value: "GlifWebSignIn"),
        ]
        return components?.url
    }

    private static func inboxURL(for email: String) -> URL? {
        URL(string: "https://mail.google.com/mail/u/?authuser=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)")
    }

    private func loadSignIn(into webView: WKWebView, email: String) {
        if let url = Self.signInURL(for: email) {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedEmail: String?
        var hasReachedInbox = false

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let email = loadedEmail, let url = webView.url else { return }
            let path = url.absoluteString

            if path.contains("mail.google.com/mail") {
                hasReachedInbox = true
                return
            }

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
    }
}

struct MailWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var renamingAccount: GoogleAccount?
    @State private var renameDraft = ""
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        VStack(spacing: 0) {
            accountTabs
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if let account = selectedAccount {
                GmailWebView(accountEmail: account.email)
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
            AccountCategoryEditorSheet(
                title: "New Category",
                actionLabel: "Sign in with Google",
                categoryName: $newCategoryName,
                onSubmit: {
                    isAddingCategory = false
                    Task {
                        await viewModel.addGoogleAccount(
                            settings: settings,
                            categoryName: newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
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
