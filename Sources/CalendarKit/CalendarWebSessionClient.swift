import Foundation
import NucleusKit

public enum CalendarWebSessionClient {
    /// Public API key embedded in Google Calendar web (session auth still required).
    private static let calendarWebAPIKey = "AIzaSyCalF5eq3dsgCFs8i7KbZfJd5Y1u0--b40"

    public static func sync(
        account: GoogleAccount,
        cookies: [HTTPCookie],
        authUserIndex: Int? = nil
    ) async -> [CalendarEventSummary] {
        guard !cookies.isEmpty else { return [] }

        if let apiEvents = await fetchEventsViaWebSessionAPI(
            account: account,
            cookies: cookies,
            preferredAuthUserIndex: authUserIndex
        ), !apiEvents.isEmpty {
            return apiEvents
        }

        let encodedEmail = account.email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.email
        let encodedQuery = account.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account.email
        let userIndex = authUserIndex ?? 0
        let candidates = [
            URL(string: "https://calendar.google.com/calendar/u/\(userIndex)/ical/primary/basic.ics?authuser=\(encodedQuery)")!,
            URL(string: "https://calendar.google.com/calendar/u/0/ical/primary/basic.ics?authuser=\(encodedQuery)")!,
            icalURL(path: "primary/basic.ics", email: account.email),
            icalURL(path: "primary/public/basic.ics", email: account.email),
            URL(string: "https://calendar.google.com/calendar/feed/ical/primary?authuser=\(encodedQuery)")!,
            URL(string: "https://calendar.google.com/calendar/ical/\(encodedEmail)/public/basic.ics?authuser=\(encodedQuery)")!,
        ]

        for url in candidates {
            if let events = await fetchEvents(url: url, cookies: cookies, account: account), !events.isEmpty {
                return events
            }
        }

        return []
    }

    public static func parseAPIEventPayloads(_ payloads: [[String: Any]], account: GoogleAccount) -> [CalendarEventSummary] {
        let now = Date()
        let horizon = upcomingHorizon(from: now)
        var seen = Set<String>()
        return payloads
            .compactMap { CalendarEventParser.parse($0, account: account) }
            .filter { event in
                guard event.endDate > now, event.startDate < horizon else { return false }
                let key = "\(event.title.lowercased())-\(Int(event.startDate.timeIntervalSince1970 / 60))"
                return seen.insert(key).inserted
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func upcomingHorizon(from now: Date) -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 8, to: startOfToday) ?? now
    }

    private static func fetchEventsViaWebSessionAPI(
        account: GoogleAccount,
        cookies: [HTTPCookie],
        preferredAuthUserIndex: Int?
    ) async -> [CalendarEventSummary]? {
        guard let authorization = GoogleSessionAuth.sapisidHash(cookies: cookies) else { return nil }

        let now = Date()
        let horizon = upcomingHorizon(from: now)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let encodedEmail = account.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account.email
        let encodedCalendarEmail = account.email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.email
        let hosts = [
            "https://clients6.google.com/calendar/v3/calendars",
            "https://www.googleapis.com/calendar/v3/calendars",
        ]

        var authUserCandidates: [String] = []
        if let preferredAuthUserIndex {
            authUserCandidates.append(String(preferredAuthUserIndex))
        }
        authUserCandidates.append(contentsOf: ["0", "1", "2", "3"])
        authUserCandidates.append(encodedEmail)
        authUserCandidates = Array(Set(authUserCandidates))

        let calendarIDs = ["primary", encodedCalendarEmail]

        for authUser in authUserCandidates {
            let headerAuthUser = Int(authUser).map(String.init) ?? authUserCandidates.first(where: { Int($0) != nil }) ?? "0"
            let listedCalendarIDs = await fetchSelectedCalendarIDs(
                cookies: cookies,
                authorization: authorization,
                authUser: authUser,
                authUserHeader: headerAuthUser
            )
            let calendarsToQuery = listedCalendarIDs ?? calendarIDs
            var aggregatedPayloads: [[String: Any]] = []

            for calendarID in calendarsToQuery {
                for host in hosts {
                    let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
                    var components = URLComponents(string: "\(host)/\(encodedCalendarID)/events")!
                    components.queryItems = [
                        URLQueryItem(name: "key", value: calendarWebAPIKey),
                        URLQueryItem(name: "calendarId", value: calendarID),
                        URLQueryItem(name: "singleEvents", value: "true"),
                        URLQueryItem(name: "orderBy", value: "startTime"),
                        URLQueryItem(name: "maxResults", value: "100"),
                        URLQueryItem(name: "timeMin", value: formatter.string(from: now)),
                        URLQueryItem(name: "timeMax", value: formatter.string(from: horizon)),
                        URLQueryItem(name: "authuser", value: authUser),
                    ]

                    guard let url = components.url else { continue }
                    if let payloads = await fetchAPIPayloads(
                        url: url,
                        cookies: cookies,
                        authorization: authorization,
                        authUserHeader: headerAuthUser
                    ), !payloads.isEmpty {
                        aggregatedPayloads.append(contentsOf: payloads)
                    }
                }
            }

            let events = parseAPIEventPayloads(aggregatedPayloads, account: account)
            if !events.isEmpty {
                return events
            }
        }

        return nil
    }

    private static func fetchSelectedCalendarIDs(
        cookies: [HTTPCookie],
        authorization: String,
        authUser: String,
        authUserHeader: String
    ) async -> [String]? {
        let hosts = [
            "https://clients6.google.com/calendar/v3/users/me/calendarList",
            "https://www.googleapis.com/calendar/v3/users/me/calendarList",
        ]

        for host in hosts {
            var components = URLComponents(string: host)!
            components.queryItems = [
                URLQueryItem(name: "key", value: calendarWebAPIKey),
                URLQueryItem(name: "minAccessRole", value: "reader"),
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "authuser", value: authUser),
            ]
            guard let url = components.url else { continue }
            guard let json = await fetchAPIJSON(
                url: url,
                cookies: cookies,
                authorization: authorization,
                authUserHeader: authUserHeader
            ) else { continue }
            guard let items = json["items"] as? [[String: Any]], !items.isEmpty else { continue }

            let calendarIDs = items.compactMap { item -> String? in
                if item["hidden"] as? Bool == true { return nil }
                if item["selected"] as? Bool == false { return nil }
                return item["id"] as? String
            }
            if !calendarIDs.isEmpty {
                return calendarIDs
            }
        }

        return nil
    }

    private static func fetchAPIJSON(
        url: URL,
        cookies: [HTTPCookie],
        authorization: String,
        authUserHeader: String
    ) async -> [String: Any]? {
        do {
            let storage = HTTPCookieStorage()
            cookies.forEach { storage.setCookie($0) }

            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = storage
            config.httpShouldSetCookies = true
            config.timeoutIntervalForRequest = 25

            var request = URLRequest(url: url)
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            request.setValue(authUserHeader, forHTTPHeaderField: "X-Goog-AuthUser")
            let cookieHeader = GoogleSessionAuth.cookieHeader(from: cookies)
            if !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://calendar.google.com", forHTTPHeaderField: "Origin")
            request.setValue("https://calendar.google.com/calendar/u/\(authUserHeader)/r/week", forHTTPHeaderField: "Referer")

            let (data, response) = try await URLSession(configuration: config).data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func fetchAPIPayloads(
        url: URL,
        cookies: [HTTPCookie],
        authorization: String,
        authUserHeader: String
    ) async -> [[String: Any]]? {
        do {
            let storage = HTTPCookieStorage()
            cookies.forEach { storage.setCookie($0) }

            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = storage
            config.httpShouldSetCookies = true
            config.timeoutIntervalForRequest = 25

            var request = URLRequest(url: url)
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            request.setValue(authUserHeader, forHTTPHeaderField: "X-Goog-AuthUser")
            let cookieHeader = GoogleSessionAuth.cookieHeader(from: cookies)
            if !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://calendar.google.com", forHTTPHeaderField: "Origin")
            request.setValue("https://calendar.google.com/calendar/u/\(authUserHeader)/r/week", forHTTPHeaderField: "Referer")

            let (data, response) = try await URLSession(configuration: config).data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let items = json?["items"] as? [[String: Any]] {
                return items
            }
            return []
        } catch {
            return nil
        }
    }

    public static func parseICS(_ text: String, account: GoogleAccount) -> [CalendarEventSummary] {
        guard text.contains("BEGIN:VCALENDAR") else { return [] }
        return parseICSEvents(text, account: account)
    }

    public static func mergeEvents(
        icalEvents: [CalendarEventSummary],
        webEvents: [CalendarEventSummary]
    ) -> [CalendarEventSummary] {
        guard !webEvents.isEmpty else { return icalEvents }
        guard !icalEvents.isEmpty else { return webEvents }

        var merged = icalEvents
        let existingTitles = Set(icalEvents.map { normalizedKey($0) })
        for event in webEvents where !existingTitles.contains(normalizedKey(event)) {
            merged.append(event)
        }
        return merged.sorted { $0.startDate < $1.startDate }
    }

    private static func normalizedKey(_ event: CalendarEventSummary) -> String {
        "\(event.title.lowercased())-\(Int(event.startDate.timeIntervalSince1970 / 60))"
    }

    private static func icalURL(path: String, email: String) -> URL {
        var components = URLComponents(string: "https://calendar.google.com/calendar/ical/\(path)")!
        components.queryItems = [
            URLQueryItem(name: "authuser", value: email),
        ]
        return components.url!
    }

    private static func fetchEvents(
        url: URL,
        cookies: [HTTPCookie],
        account: GoogleAccount
    ) async -> [CalendarEventSummary]? {
        do {
            let (data, response) = try await fetchICS(url: url, cookies: cookies)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
                return nil
            }
            let events = parseICSEvents(text, account: account)
            return events.isEmpty ? nil : events
        } catch {
            return nil
        }
    }

    private static func fetchICS(url: URL, cookies: [HTTPCookie]) async throws -> (Data, URLResponse) {
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
        request.setValue("https://calendar.google.com/", forHTTPHeaderField: "Referer")
        let cookieHeader = GoogleSessionAuth.cookieHeader(from: cookies)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        return try await URLSession(configuration: config).data(for: request)
    }

    private static func parseICSEvents(_ text: String, account: GoogleAccount) -> [CalendarEventSummary] {
        let unfolded = unfoldICS(text)
        let now = Date()
        let horizon = upcomingHorizon(from: now)
        var events: [CalendarEventSummary] = []
        var current: [String: String] = [:]

        for rawLine in unfolded.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "BEGIN:VEVENT" {
                current = [:]
                continue
            }
            if line == "END:VEVENT" {
                if let event = makeEvent(from: current, account: account, now: now, horizon: horizon) {
                    events.append(event)
                }
                current = [:]
                continue
            }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let keyPart = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            let key = keyPart.split(separator: ";").first.map(String.init) ?? keyPart
            current[keyPart] = value
            if current[key] == nil {
                current[key] = value
            }
        }

        return events.sorted { $0.startDate < $1.startDate }
    }

    private static func unfoldICS(_ text: String) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(String(line))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func makeEvent(
        from fields: [String: String],
        account: GoogleAccount,
        now: Date,
        horizon: Date
    ) -> CalendarEventSummary? {
        guard let uid = fields["UID"], let summary = fields["SUMMARY"] else { return nil }
        guard !CalendarJunkFilter.isCalendarChromeTitle(summary) else { return nil }
        let startKey = fields.keys.first(where: { $0.hasPrefix("DTSTART") && $0.contains("TZID=") })
            ?? fields.keys.first(where: { $0.hasPrefix("DTSTART") })
            ?? "DTSTART"
        let endKey = fields.keys.first(where: { $0.hasPrefix("DTEND") && $0.contains("TZID=") })
            ?? fields.keys.first(where: { $0.hasPrefix("DTEND") })
            ?? "DTEND"
        guard let startDate = parseICSDate(key: startKey, value: fields[startKey] ?? fields["DTSTART"]) else {
            return nil
        }
        let endDate = parseICSDate(key: endKey, value: fields[endKey] ?? fields["DTEND"])
            ?? startDate.addingTimeInterval(3600)
        guard endDate > now, startDate < horizon else { return nil }

        let location = fields["LOCATION"] ?? ""
        let description = fields["DESCRIPTION"]?.replacingOccurrences(of: "\\n", with: "\n") ?? ""
        let meetingLink = MeetingLinkExtractor.extract(description: description, location: location)

        return CalendarEventSummary(
            id: "\(account.id.uuidString)-\(uid)",
            accountID: account.id,
            title: summary,
            startDate: startDate,
            endDate: endDate,
            location: location,
            attendees: [],
            meetingLink: meetingLink,
            accountEmail: account.email
        )
    }

    private static func parseICSDate(key: String, value: String?) -> Date? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if key.localizedCaseInsensitiveContains("TZID="),
           let tzid = key.split(separator: ";").first(where: { $0.uppercased().hasPrefix("TZID=") })?.dropFirst(5) {
            formatter.timeZone = TimeZone(identifier: String(tzid)) ?? .current
        } else if cleaned.hasSuffix("Z") {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
        } else {
            formatter.timeZone = .current
        }

        let formats = [
            "yyyyMMdd'T'HHmmssX",
            "yyyyMMdd'T'HHmmss'Z'",
            "yyyyMMdd'T'HHmmss",
            "yyyyMMdd",
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return date
            }
        }
        return nil
    }

    private static func parseICSDate(_ value: String?) -> Date? {
        parseICSDate(key: "DTSTART", value: value)
    }

}
