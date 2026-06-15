import Foundation
import NucleusKit

public enum CalendarWebSessionClient {
    public static func sync(account: GoogleAccount, cookies: [HTTPCookie]) async -> [CalendarEventSummary] {
        guard !cookies.isEmpty else { return [] }

        let encodedEmail = account.email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.email
        let encodedQuery = account.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account.email
        let candidates = [
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
            let events = parseICS(text, account: account)
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

        return try await URLSession(configuration: config).data(for: request)
    }

    private static func parseICS(_ text: String, account: GoogleAccount) -> [CalendarEventSummary] {
        let unfolded = unfoldICS(text)
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
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
        guard endDate > now, startDate <= horizon else { return nil }

        let location = fields["LOCATION"] ?? ""
        let description = fields["DESCRIPTION"]?.replacingOccurrences(of: "\\n", with: "\n") ?? ""
        let meetingLink = extractMeetingLink(description: description, location: location)

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

    private static func extractMeetingLink(description: String, location: String) -> String? {
        if location.hasPrefix("http") { return location }
        let patterns = [
            "https://meet.google.com/[a-z-]+",
            "https://[a-z0-9.-]+\\.zoom.us/j/[0-9?=&]+",
            "https://teams.microsoft.com/l/meetup-join/[^\\s]+",
        ]
        for pattern in patterns {
            if let range = description.range(of: pattern, options: .regularExpression) {
                return String(description[range])
            }
        }
        return nil
    }
}
