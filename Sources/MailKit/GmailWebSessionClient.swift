import Foundation
import NucleusKit

public enum GmailWebSessionClient {
    public static func sync(
        account: GoogleAccount,
        cookies: [HTTPCookie],
        knownMessageIDs: Set<String>
    ) async -> MailSyncResult {
        guard !cookies.isEmpty else {
            return MailSyncResult(unreadByAccount: [account.id: 0], messages: [], newMessages: [])
        }

        do {
            let feedURL = atomFeedURL(for: account.email)
            let (data, response) = try await fetchFeed(url: feedURL, cookies: cookies)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return MailSyncResult(unreadByAccount: [account.id: 0], messages: [], newMessages: [])
            }
            guard let xml = String(data: data, encoding: .utf8), xml.contains("<feed") else {
                return MailSyncResult(unreadByAccount: [account.id: 0], messages: [], newMessages: [])
            }

            let feedUnread = parseFeedUnreadCount(xml)
            let messages = parseAtomFeed(xml, accountID: account.id)
            let unreadCount = max(feedUnread, messages.filter(\.isUnread).count)
            let newMessages = messages.filter { !knownMessageIDs.contains($0.id) && $0.isUnread }
            return MailSyncResult(
                unreadByAccount: [account.id: unreadCount],
                messages: messages,
                newMessages: newMessages
            )
        } catch {
            return MailSyncResult(unreadByAccount: [account.id: 0], messages: [], newMessages: [])
        }
    }

    private static func atomFeedURL(for email: String) -> URL {
        var components = URLComponents(string: "https://mail.google.com/mail/u/0/feed/atom")!
        components.queryItems = [
            URLQueryItem(name: "authuser", value: email),
        ]
        return components.url!
    }

    private static func fetchFeed(url: URL, cookies: [HTTPCookie]) async throws -> (Data, URLResponse) {
        let storage = HTTPCookieStorage()
        cookies.forEach { storage.setCookie($0) }

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = storage
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let session = URLSession(configuration: config)
        return try await session.data(for: request)
    }

    private static func parseAtomFeed(_ xml: String, accountID: UUID) -> [MailMessageSummary] {
        let parser = GmailAtomParser(accountID: accountID)
        parser.parse(xml)
        return parser.messages
    }

    private static func parseFeedUnreadCount(_ xml: String) -> Int {
        guard let range = xml.range(of: "<fullcount>(\\d+)</fullcount>", options: .regularExpression) else {
            return 0
        }
        let match = String(xml[range])
        let digits = match.filter(\.isNumber)
        return Int(digits) ?? 0
    }
}

private final class GmailAtomParser: NSObject, XMLParserDelegate {
    private let accountID: UUID
    private(set) var messages: [MailMessageSummary] = []

    private var currentEntry: AtomEntry?
    private var insideAuthor = false
    private var currentText = ""

    init(accountID: UUID) {
        self.accountID = accountID
    }

    func parse(_ xml: String) {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        if elementName == "entry" {
            currentEntry = AtomEntry()
        } else if elementName == "author" {
            insideAuthor = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var entry = currentEntry else { return }

        switch elementName {
        case "title":
            entry.title = value
        case "summary":
            entry.summary = value
        case "id":
            entry.id = value
        case "name" where insideAuthor:
            entry.authorName = value
        case "email" where insideAuthor:
            entry.authorEmail = value
        case "modified", "issued", "updated":
            if entry.receivedAt == nil {
                entry.receivedAt = ISO8601DateFormatter().date(from: value)
                    ?? parseAtomDate(value)
            }
        case "author":
            insideAuthor = false
        case "entry":
            if let message = entry.makeMessage(accountID: accountID) {
                messages.append(message)
            }
            currentEntry = nil
        default:
            break
        }

        if currentEntry != nil {
            currentEntry = entry
        }
    }

    private func parseAtomDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.date(from: value)
    }
}

private struct AtomEntry {
    var id = ""
    var title = ""
    var summary = ""
    var authorName = ""
    var authorEmail = ""
    var receivedAt: Date?

    func makeMessage(accountID: UUID) -> MailMessageSummary? {
        guard !id.isEmpty else { return nil }
        let messageID = id.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? id
        return MailMessageSummary(
            id: messageID,
            accountID: accountID,
            threadID: messageID,
            fromName: authorName.isEmpty ? authorEmail : authorName,
            fromEmail: authorEmail,
            subject: title.isEmpty ? "(No subject)" : title,
            snippet: summary,
            receivedAt: receivedAt ?? Date(),
            isUnread: true
        )
    }
}
