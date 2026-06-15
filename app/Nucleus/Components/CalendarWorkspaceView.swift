import AccountKit
import NucleusKit
import SwiftUI
import WebKit

struct CalendarWebView: NSViewRepresentable {
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
        context.coordinator.accountEmail = accountEmail
        loadCalendar(into: webView, email: accountEmail)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.accountEmail != accountEmail else { return }
        context.coordinator.accountEmail = accountEmail
        loadCalendar(into: webView, email: accountEmail)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func calendarURL(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://calendar.google.com/calendar/u/0/r/week?authuser=\(encoded)")
    }

    private static func signInURL(for email: String) -> URL? {
        guard let continueTarget = calendarURL(for: email)?.absoluteString else { return nil }
        var components = URLComponents(string: "https://accounts.google.com/v3/signin/identifier")
        components?.queryItems = [
            URLQueryItem(name: "service", value: "cl"),
            URLQueryItem(name: "continue", value: continueTarget),
            URLQueryItem(name: "Email", value: email),
            URLQueryItem(name: "flowName", value: "GlifWebSignIn"),
            URLQueryItem(name: "flowEntry", value: "ServiceLogin"),
        ]
        return components?.url
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
    }
}

struct CalendarWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            accountTabs
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if let account = selectedAccount {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if account.authMode == .webSession {
                            CalendarWebView(accountID: account.id, accountEmail: account.email)
                                .id(account.id)
                                .frame(minHeight: 420)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        upcomingEvents(for: account)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ContentUnavailableView(
                    "No calendar account selected",
                    systemImage: "calendar",
                    description: Text("Add a Google account to view calendars and meeting reminders.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        let eventCount = viewModel.calendarEvents(for: account.id).count
                        HStack(spacing: 8) {
                            Text(account.displayName)
                                .font(.subheadline.weight(.semibold))
                            if eventCount > 0 {
                                Text("\(eventCount)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.purple.opacity(0.85), in: Capsule())
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

    @ViewBuilder
    private func upcomingEvents(for account: GoogleAccount) -> some View {
        let events = viewModel.calendarEvents(for: account.id)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upcoming")
                    .font(.title3.bold())
                Text("Meetings for \(account.displayName) in the next 7 days.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            if events.isEmpty {
                ContentUnavailableView(
                    account.authMode == .webSession ? "No synced events yet" : "No upcoming events",
                    systemImage: "calendar.badge.clock",
                    description: Text(
                        account.authMode == .webSession
                            ? "Sign in to Google Calendar above. Events sync automatically for meeting alerts."
                            : "Your calendar will appear here after the next sync."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(events) { event in
                    CalendarEventCard(event: event, accountName: account.displayName)
                }
            }
        }
    }
}

private struct CalendarEventCard: View {
    let event: CalendarEventSummary
    let accountName: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NucleusFormatters.time.string(from: event.startDate))
                    .font(.headline.monospacedDigit())
                Text(NucleusFormatters.time.string(from: event.endDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.headline)
                Text(accountName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !event.attendees.isEmpty {
                    Text(event.attendees.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let link = event.meetingLink, let url = URL(string: link) {
                    Button("Join Meeting") {
                        ChromeLauncher.open(url: url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}
