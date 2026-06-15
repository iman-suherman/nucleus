import AccountKit
import CalendarKit
import NucleusKit
import SwiftUI
import WebKit

extension Notification.Name {
    static let calendarWebEventsDidChange = Notification.Name("CalendarWebEventsDidChange")
    static let calendarWebEventsPollNow = Notification.Name("CalendarWebEventsPollNow")
}

struct CalendarWebView: NSViewRepresentable {
    let accountID: UUID
    let accountEmail: String

    fileprivate static let syncMessageHandlerName = "nucleusCalendarSync"

    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = GmailWebSessionStore.dataStore(for: accountID)
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.add(context.coordinator, name: Self.syncMessageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = Self.safariUserAgent
        context.coordinator.accountID = accountID
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

    static func authUserIndex(from url: URL) -> Int? {
        CalendarWebAuthIndexStore.index(from: url)
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var accountID: UUID?
        var accountEmail: String?
        private var eventPollTimer: Timer?
        private var pollNowObserver: NSObjectProtocol?
        private var lastReportedAuthUserIndex: Int?

        deinit {
            eventPollTimer?.invalidate()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == CalendarWebView.syncMessageHandlerName,
                  let accountID else { return }
            handleSyncMessage(message.body, accountID: accountID)
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

            if path.contains("calendar.google.com/calendar") {
                if let accountID, let index = CalendarWebView.authUserIndex(from: url) {
                    CalendarWebAuthIndexStore.setIndex(index, for: accountID)
                    lastReportedAuthUserIndex = index
                }
                startEventPolling(in: webView)
                return
            }

            stopEventPolling()

            let isMarketingLanding =
                path.contains("workspace.google.com/products/calendar")
                || path.contains("google.com/calendar/about")
                || (path.contains("google.com") && !path.contains("accounts.google.com") && !path.contains("calendar.google.com"))

            if isMarketingLanding, let signInURL = CalendarWebView.signInURL(for: email) {
                webView.load(URLRequest(url: signInURL))
            }
        }

        private func startEventPolling(in webView: WKWebView) {
            stopEventPolling()
            reportEvents(from: webView)
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self, weak webView] _ in
                guard let webView else { return }
                self?.reportEvents(from: webView)
            }
            RunLoop.main.add(timer, forMode: .common)
            eventPollTimer = timer

            pollNowObserver = NotificationCenter.default.addObserver(
                forName: .calendarWebEventsPollNow,
                object: nil,
                queue: .main
            ) { [weak self, weak webView] _ in
                guard let webView else { return }
                self?.reportEvents(from: webView)
            }
        }

        private func stopEventPolling() {
            eventPollTimer?.invalidate()
            eventPollTimer = nil
            if let pollNowObserver {
                NotificationCenter.default.removeObserver(pollNowObserver)
                self.pollNowObserver = nil
            }
        }

        private func reportEvents(from webView: WKWebView) {
            guard let accountID, let accountEmail else { return }
            let authUserIndex = CalendarWebAuthIndexStore.index(for: accountID) ?? lastReportedAuthUserIndex ?? 0
            let script = CalendarWebView.eventSyncScript(for: accountEmail, authUserIndex: authUserIndex)
            webView.evaluateJavaScript(script, completionHandler: { _, _ in })
        }

        private func handleSyncMessage(_ body: Any, accountID: UUID) {
            let payload: [String: Any]
            if let dictionary = body as? [String: Any] {
                payload = dictionary
            } else if let jsonString = body as? String,
                      let data = jsonString.data(using: .utf8),
                      let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payload = dictionary
            } else {
                return
            }

            guard let entriesJSON = payload["entriesJSON"] as? String else { return }
            let icsText = payload["icsText"] as? String
            let apiPayloads = decodeAPIPayloads(from: payload["apiItemsJSON"])

            guard entriesJSON != "[]" || !(icsText?.isEmpty ?? true) || !apiPayloads.isEmpty else { return }

            var userInfo: [String: Any] = [
                "accountID": accountID.uuidString,
                "entriesJSON": entriesJSON,
            ]
            if let icsText, !icsText.isEmpty {
                userInfo["icsText"] = icsText
            }
            if !apiPayloads.isEmpty {
                userInfo["apiPayloads"] = apiPayloads
            }

            NotificationCenter.default.post(
                name: .calendarWebEventsDidChange,
                object: nil,
                userInfo: userInfo
            )
        }

        private func decodeAPIPayloads(from value: Any?) -> [[String: Any]] {
            if let payloads = value as? [[String: Any]] {
                return payloads
            }
            if let jsonString = value as? String,
               let data = jsonString.data(using: .utf8),
               let payloads = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return payloads
            }
            return []
        }
    }
}

private extension CalendarWebView {
    static func eventSyncScript(for email: String, authUserIndex: Int) -> String {
        let escapedEmail = email
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function() {
          const authEmail = '\(escapedEmail)';
          const authUserIndex = \(authUserIndex);
          const apiKey = 'AIzaSyCalF5eq3dsgCFs8i7KbZfJd5Y1u0--b40';
          const entries = [];
          const seen = new Set();
          const timePattern = /(\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|am|pm)?)\\s*(?:–|-|—|to)\\s*(\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|am|pm)?)/i;

          function postPayload(payload) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nucleusCalendarSync) {
              window.webkit.messageHandlers.nucleusCalendarSync.postMessage(payload);
            }
          }

          function isChromeSegment(title) {
            const lower = (title || '').trim().toLowerCase();
            if (!lower) return true;
            if (lower.startsWith('add a ') && lower.includes('location')) return true;
            if (lower.startsWith('add ') && lower.endsWith(' location')) return true;
            if (lower.startsWith('change ') && lower.includes('location')) return true;
            if (lower.startsWith('working location')) return true;
            return /^(add a working location|add working location|add location|change working location|change work location|add title|create event|create meeting|create task|add note|more options|join with google meet)$/.test(lower);
          }

          function isChromeTitle(title) {
            const trimmed = (title || '').trim();
            if (!trimmed) return true;
            if (isChromeSegment(trimmed)) return true;
            const comma = trimmed.indexOf(',');
            if (comma > 0) {
              return isChromeSegment(trimmed.slice(0, comma));
            }
            return false;
          }

          function isPickerNode(node) {
            if (!node) return false;
            if (node.getAttribute('data-is-picker') === 'true') return true;
            return node.closest('[data-is-picker="true"]') != null;
          }

          function addLabel(label) {
            const trimmed = (label || '').trim();
            if (!trimmed || trimmed.length < 2 || seen.has(trimmed) || isChromeTitle(trimmed)) return;
            seen.add(trimmed);
            const match = trimmed.match(timePattern);
            entries.push({
              label: trimmed,
              start: match ? match[1].trim() : null,
              end: match ? match[2].trim() : null
            });
          }

          function collectEventLabels() {
            document.querySelectorAll('[data-eventid], [data-eventchip], [data-event-id]').forEach(function(node) {
              if (isPickerNode(node)) return;
              addLabel(node.getAttribute('aria-label'));
              const nested = node.querySelector('[aria-label]');
              if (nested && !isPickerNode(nested)) addLabel(nested.getAttribute('aria-label'));
            });

            document.querySelectorAll('[role="gridcell"]').forEach(function(cell) {
              const dayHint = (cell.getAttribute('aria-label') || '').trim();
              cell.querySelectorAll('[data-eventid], [data-eventchip], [data-event-id]').forEach(function(node) {
                if (isPickerNode(node)) return;
                const label = node.getAttribute('aria-label');
                if (label && dayHint && !label.includes(',')) {
                  addLabel(label + ', ' + dayHint);
                } else {
                  addLabel(label);
                }
              });
            });
          }

          collectEventLabels();

          async function authHeader() {
            const match = document.cookie.match(/(?:^|;\\s*)(?:SAPISID|__Secure-1PAPISID|__Secure-3PAPISID)=([^;]+)/);
            if (!match) return null;
            const t = Math.floor(Date.now() / 1000);
            const input = t + ' ' + decodeURIComponent(match[1]) + ' https://calendar.google.com';
            const digest = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(input));
            const hash = Array.from(new Uint8Array(digest)).map(function(b) {
              return b.toString(16).padStart(2, '0');
            }).join('');
            return 'SAPISIDHASH ' + t + '_' + hash;
          }

          async function fetchCalendarList(authorization, authUser, headerAuthUser) {
            const listHosts = [
              'https://clients6.google.com/calendar/v3/users/me/calendarList',
              'https://www.googleapis.com/calendar/v3/users/me/calendarList'
            ];
            for (const host of listHosts) {
              const url = host + '?key=' + apiKey
                + '&minAccessRole=reader&maxResults=250'
                + '&authuser=' + encodeURIComponent(authUser);
              try {
                const resp = await fetch(url, {
                  credentials: 'include',
                  headers: {
                    Authorization: authorization,
                    'X-Goog-AuthUser': headerAuthUser
                  }
                });
                if (!resp.ok) continue;
                const json = await resp.json();
                if (!json || !Array.isArray(json.items) || !json.items.length) continue;
                const ids = json.items
                  .filter(function(item) { return item.hidden !== true && item.selected !== false; })
                  .map(function(item) { return item.id; })
                  .filter(Boolean);
                if (ids.length) return ids;
              } catch (e) {}
            }
            return null;
          }

          async function fetchApiItems() {
            const authorization = await authHeader();
            if (!authorization) return [];
            const timeMin = new Date().toISOString();
            const timeMax = new Date(Date.now() + 8 * 24 * 60 * 60 * 1000).toISOString();
            const authUsers = [String(authUserIndex), '0', '1', '2', '3', authEmail];
            const fallbackCalendarIds = ['primary', authEmail];
            const hosts = [
              'https://clients6.google.com/calendar/v3/calendars',
              'https://www.googleapis.com/calendar/v3/calendars'
            ];

            for (const authUser of authUsers) {
              const headerAuthUser = /^\\d+$/.test(authUser) ? authUser : String(authUserIndex);
              const calendarIds = await fetchCalendarList(authorization, authUser, headerAuthUser) || fallbackCalendarIds;
              const allItems = [];
              const seenIds = new Set();
              for (const calendarId of calendarIds) {
                for (const host of hosts) {
                  const url = host + '/' + encodeURIComponent(calendarId) + '/events?key=' + apiKey
                    + '&calendarId=' + encodeURIComponent(calendarId)
                    + '&singleEvents=true&orderBy=startTime&maxResults=100'
                    + '&timeMin=' + encodeURIComponent(timeMin)
                    + '&timeMax=' + encodeURIComponent(timeMax)
                    + '&authuser=' + encodeURIComponent(authUser);
                  try {
                    const resp = await fetch(url, {
                      credentials: 'include',
                      headers: {
                        Authorization: authorization,
                        'X-Goog-AuthUser': headerAuthUser
                      }
                    });
                    if (!resp.ok) continue;
                    const json = await resp.json();
                    if (!json || !Array.isArray(json.items)) continue;
                    json.items.forEach(function(item) {
                      if (item && item.id && !seenIds.has(item.id)) {
                        seenIds.add(item.id);
                        allItems.push(item);
                      }
                    });
                  } catch (e) {}
                }
              }
              if (allItems.length) return allItems;
            }
            return [];
          }

          (async function() {
            let ics = null;
            let apiItems = [];
            const authuser = encodeURIComponent(authEmail);
            const paths = [
              '/calendar/u/' + authUserIndex + '/ical/primary/basic.ics?authuser=' + authuser,
              '/calendar/u/0/ical/primary/basic.ics?authuser=' + authuser,
              '/calendar/ical/primary/basic.ics?authuser=' + authuser,
              '/calendar/feed/ical/primary?authuser=' + authuser,
            ];
            apiItems = await fetchApiItems();
            for (const path of paths) {
              try {
                const resp = await fetch('https://calendar.google.com' + path, { credentials: 'include' });
                if (!resp.ok) continue;
                const text = await resp.text();
                if (text.includes('BEGIN:VCALENDAR')) {
                  ics = text;
                  break;
                }
              } catch (e) {}
            }
            postPayload({
              entriesJSON: JSON.stringify(entries.slice(0, 120)),
              icsText: ics,
              apiItemsJSON: JSON.stringify(apiItems)
            });
          })();
        })();
        """
    }
}

struct CalendarWebPoller: View {
    let accountID: UUID
    let accountEmail: String

    var body: some View {
        CalendarWebView(accountID: accountID, accountEmail: accountEmail)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }
}

struct CalendarWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            accountTabs
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)

            if let account = selectedAccount {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if account.authMode == .webSession {
                            CalendarWebView(accountID: account.id, accountEmail: account.email)
                                .id("calendar-\(account.id)")
                                .frame(minHeight: 420)
                                .padding(.horizontal, 12)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        upcomingEvents(for: account)
                            .padding(16)
                    }
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
        HStack(spacing: 8) {
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
                                    NucleusCountBadge(count: eventCount)
                                }
                            }
                            .nucleusAccountTab(isSelected: selectedAccount?.id == account.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            CalendarSyncButton()
        }
    }

    @ViewBuilder
    private func upcomingEvents(for account: GoogleAccount) -> some View {
        let events = viewModel.calendarEvents(for: account.id)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upcoming")
                        .font(.title3.bold())
                    Text("Meetings for \(account.displayName) in the next 7 days.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                Spacer()

                CalendarSyncButton(compact: true)
            }

            if events.isEmpty {
                ContentUnavailableView(
                    "No upcoming events synced",
                    systemImage: "calendar.badge.clock",
                    description: Text(
                        account.authMode == .webSession
                            ? "Tap Sync to pull events from Google Calendar and refresh meeting alerts."
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

struct CalendarSyncButton: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var compact = false

    var body: some View {
        Button {
            viewModel.syncCalendarNow()
        } label: {
            if viewModel.isSyncingCalendar {
                ProgressView()
                    .controlSize(.small)
            } else if compact {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
            } else {
                Label("Sync Calendar", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .nucleusAccountTab(isSelected: false)
        .disabled(viewModel.isSyncingCalendar)
        .help("Sync Google Calendar and refresh meeting notifications")
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
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
