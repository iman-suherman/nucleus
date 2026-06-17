import Foundation
import OSLog

struct DashboardNewsHeadline: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let publishedAt: Date?
    let link: URL?
}

enum DashboardNewsFeedClient {
    static func feedURL(countryCode: String) -> URL {
        let region = countryCode.uppercased()
        let language = region == "US" ? "en-US" : "en-\(region)"
        return URL(string: "https://news.google.com/rss?hl=\(language)&gl=\(region)&ceid=\(region):en")!
    }

    static func fetchHeadlines(countryCode: String, limit: Int = 20) async throws -> [DashboardNewsHeadline] {
        let url = feedURL(countryCode: countryCode)
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let headlines = RSSFeedParser.parse(data: data)
        return Array(headlines.prefix(limit))
    }
}

private enum RSSFeedParser {
    static func parse(data: Data) -> [DashboardNewsHeadline] {
        let parser = RSSParser()
        parser.parse(data)
        return parser.headlines
    }
}

private final class RSSParser: NSObject, XMLParserDelegate {
    private(set) var headlines: [DashboardNewsHeadline] = []

    private var insideItem = false
    private var currentTitle = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var currentDescription = ""
    private var currentElement = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
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
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentLink = attributeDict["href"] ?? ""
            currentPubDate = ""
            currentDescription = ""
        } else if elementName == "link", insideItem, currentLink.isEmpty {
            currentLink = attributeDict["href"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "link" where currentLink.isEmpty:
            currentLink += string
        case "pubDate":
            currentPubDate += string
        case "description", "encoded":
            currentDescription += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "item", insideItem else { return }
        insideItem = false

        let title = RSSPlainText.sanitizeCDATA(currentTitle)
        guard !title.isEmpty else { return }

        let linkURL = URL(string: currentLink.trimmingCharacters(in: .whitespacesAndNewlines))
        let publishedAt = RSSDateParser.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
        let id = linkURL?.absoluteString ?? title
        let summary = RSSPlainText.fromHTML(currentDescription)

        headlines.append(
            DashboardNewsHeadline(
                id: id,
                title: title,
                summary: summary,
                publishedAt: publishedAt,
                link: linkURL
            )
        )
    }
}

private enum RSSPlainText {
    static func sanitizeCDATA(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fromHTML(_ html: String) -> String {
        var text = sanitizeCDATA(html)
        guard !text.isEmpty else { return "" }

        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")

        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum RSSDateParser {
    static func date(from value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: value)
    }
}

@MainActor
final class DashboardNewsFeedService: ObservableObject {
    static let shared = DashboardNewsFeedService()

    @Published private(set) var headlines: [DashboardNewsHeadline] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    private var cachedCountryCode: String?
    private var lastFetchAt: Date?
    private var fetchTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private let logger = Logger(subsystem: "net.suherman.nucleus", category: "DashboardNewsFeed")

    private static let refreshInterval: TimeInterval = 60 * 60

    private init() {}

    func startAutoRefresh(countryCode: String?) {
        refresh(countryCode: countryCode)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(countryCode: countryCode ?? self?.cachedCountryCode, force: true)
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        fetchTask?.cancel()
        fetchTask = nil
    }

    func refresh(countryCode: String?, force: Bool = false) {
        let normalized = (countryCode ?? Locale.current.region?.identifier ?? "US").uppercased()
        if !force,
           normalized == cachedCountryCode,
           let lastFetchAt,
           Date().timeIntervalSince(lastFetchAt) < Self.refreshInterval,
           !headlines.isEmpty {
            return
        }

        fetchTask?.cancel()
        fetchTask = Task { @MainActor in
            await loadHeadlines(countryCode: normalized)
        }
    }

    private func loadHeadlines(countryCode: String) async {
        isLoading = headlines.isEmpty
        if headlines.isEmpty {
            statusMessage = nil
        }
        defer { isLoading = false }

        do {
            let fetched = try await DashboardNewsFeedClient.fetchHeadlines(countryCode: countryCode)
            guard !Task.isCancelled else { return }
            headlines = fetched
            cachedCountryCode = countryCode
            lastFetchAt = Date()
            statusMessage = fetched.isEmpty ? "No headlines available right now." : nil
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("News feed fetch failed: \(error.localizedDescription, privacy: .public)")
            if headlines.isEmpty {
                statusMessage = "Couldn't load headlines right now."
            }
        }
    }
}
