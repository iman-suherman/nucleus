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

    static func fetchHeadlines(
        countryCodes: [String],
        limitPerCountry: Int = 12,
        totalLimit: Int = 24
    ) async -> [DashboardNewsHeadline] {
        let codes = countryCodes
            .map { $0.uppercased() }
            .filter { !$0.isEmpty }

        guard !codes.isEmpty else { return [] }
        if codes.count == 1 {
            return (try? await fetchHeadlines(countryCode: codes[0], limit: totalLimit)) ?? []
        }

        var combined: [DashboardNewsHeadline] = []
        var seenIDs = Set<String>()

        await withTaskGroup(of: [DashboardNewsHeadline].self) { group in
            for code in codes {
                group.addTask {
                    (try? await fetchHeadlines(countryCode: code, limit: limitPerCountry)) ?? []
                }
            }

            for await batch in group {
                for headline in batch where seenIDs.insert(headline.id).inserted {
                    combined.append(headline)
                }
            }
        }

        combined.sort { lhs, rhs in
            switch (lhs.publishedAt, rhs.publishedAt) {
            case let (left?, right?):
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        return Array(combined.prefix(totalLimit))
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
    @Published private(set) var enrichments: [String: DashboardNewsEnrichment] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    private var cachedCountryCodes: [String] = []
    private var activeCountryCodes: [String] = []
    private var lastFetchAt: Date?
    private var fetchTask: Task<Void, Never>?
    private var enrichmentTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private let logger = Logger(subsystem: "net.suherman.nucleus", category: "DashboardNewsFeed")

    private static let refreshInterval: TimeInterval = 60 * 60

    private init() {}

    func startAutoRefresh(countryCode: String?) {
        startAutoRefresh(countryCodes: countryCode.map { [$0] } ?? [])
    }

    func startAutoRefresh(countryCodes: [String]) {
        activeCountryCodes = Self.normalizedCountryCodes(countryCodes)
        if activeCountryCodes.isEmpty {
            activeCountryCodes = [Self.fallbackCountryCode()]
        }
        refresh(countryCodes: activeCountryCodes)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh(countryCodes: self.activeCountryCodes, force: true)
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
        enrichmentTask?.cancel()
        enrichmentTask = nil
    }

    func refresh(countryCode: String?, force: Bool = false) {
        refresh(countryCodes: countryCode.map { [$0] } ?? [], force: force)
    }

    func refresh(countryCodes: [String], force: Bool = false) {
        let normalized = Self.normalizedCountryCodes(countryCodes)
        let resolved = normalized.isEmpty ? [Self.fallbackCountryCode()] : normalized
        activeCountryCodes = resolved

        if !force,
           resolved == cachedCountryCodes,
           let lastFetchAt,
           Date().timeIntervalSince(lastFetchAt) < Self.refreshInterval,
           !headlines.isEmpty {
            return
        }

        fetchTask?.cancel()
        fetchTask = Task { @MainActor in
            await loadHeadlines(countryCodes: resolved)
        }
    }

    private func loadHeadlines(countryCodes: [String]) async {
        isLoading = headlines.isEmpty
        if headlines.isEmpty {
            statusMessage = nil
        }
        defer { isLoading = false }

        let fetched = await DashboardNewsFeedClient.fetchHeadlines(countryCodes: countryCodes)
        guard !Task.isCancelled else { return }

        if fetched.isEmpty {
            logger.error("News feed fetch returned no headlines for \(countryCodes.joined(separator: ", "), privacy: .public)")
            if headlines.isEmpty {
                statusMessage = "No headlines available right now."
            }
            return
        }

        headlines = fetched
        cachedCountryCodes = countryCodes
        lastFetchAt = Date()
        statusMessage = nil
        enrichHeadlines(fetched)
    }

    private func enrichHeadlines(_ items: [DashboardNewsHeadline]) {
        enrichmentTask?.cancel()

        var seeded = enrichments
        for headline in items {
            if seeded[headline.id] == nil,
               let cached = DashboardNewsAnalysisService.cachedEnrichment(for: headline) {
                seeded[headline.id] = cached
            }
        }
        enrichments = seeded

        enrichmentTask = Task { @MainActor in
            var updated = seeded
            for headline in items {
                guard !Task.isCancelled else { return }
                let enrichment = await DashboardNewsAnalysisService.resolveEnrichment(for: headline)
                updated[headline.id] = enrichment
                enrichments = updated
            }
        }
    }

    func enrichment(for headline: DashboardNewsHeadline) -> DashboardNewsEnrichment {
        if let cached = enrichments[headline.id] {
            return cached
        }
        return DashboardNewsAnalysisService.fallbackEnrichment(for: headline)
    }

    private static func normalizedCountryCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for code in codes {
            let upper = code.uppercased()
            guard upper.count == 2, seen.insert(upper).inserted else { continue }
            normalized.append(upper)
        }
        return normalized
    }

    private static func fallbackCountryCode() -> String {
        (Locale.current.region?.identifier ?? "US").uppercased()
    }
}
