import Foundation
import NucleusKit

public enum CalendarAPIClient {
    public static func fetchUpcomingEvents(accessToken: String, daysAhead: Int = 7) async throws -> [[String: Any]] {
        let calendar = Calendar.current
        let start = Date()
        let end = calendar.date(byAdding: .day, value: daysAhead, to: start) ?? start

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
            URLQueryItem(name: "maxResults", value: "50"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["items"] as? [[String: Any]] ?? []
    }
}

public enum CalendarEventParser {
    public static func parse(_ payload: [String: Any], account: GoogleAccount) -> CalendarEventSummary? {
        if let status = payload["status"] as? String, status == "cancelled" {
            return nil
        }
        if let eventType = payload["eventType"] as? String, eventType == "workingLocation" {
            return nil
        }

        guard let id = payload["id"] as? String else { return nil }
        let title = payload["summary"] as? String ?? "(Untitled meeting)"
        guard !CalendarJunkFilter.isCalendarChromeTitle(title) else { return nil }

        guard let startDate = parseEventDate(payload["start"] as? [String: Any], isEnd: false) else {
            return nil
        }
        let endDate = parseEventDate(payload["end"] as? [String: Any], isEnd: true)
            ?? startDate.addingTimeInterval(3600)
        guard endDate > startDate else { return nil }

        let location = payload["location"] as? String ?? ""

        var attendees: [String] = []
        if let attendeeItems = payload["attendees"] as? [[String: Any]] {
            attendees = attendeeItems.compactMap { $0["email"] as? String }
        }

        let meetingLink = extractMeetingLink(from: payload)

        return CalendarEventSummary(
            id: "\(account.id.uuidString)-\(id)",
            accountID: account.id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location,
            attendees: attendees,
            meetingLink: meetingLink,
            accountEmail: account.email
        )
    }

    private static func parseEventDate(_ payload: [String: Any]?, isEnd: Bool) -> Date? {
        guard let payload else { return nil }
        if let dateTime = payload["dateTime"] as? String {
            return parseDateTimeString(dateTime)
        }
        if let date = payload["date"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            guard let day = formatter.date(from: date) else { return nil }
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: day)
            if isEnd {
                return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            }
            return startOfDay
        }
        return nil
    }

    private static func parseDateTimeString(_ value: String) -> Date? {
        let isoOptions: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
            [.withFullDate, .withFullTime, .withColonSeparatorInTimeZone],
            [.withFullDate, .withFullTime, .withTimeZone],
        ]
        for options in isoOptions {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) {
                return date
            }
        }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
        ] {
            fallback.dateFormat = format
            if let date = fallback.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func extractMeetingLink(from payload: [String: Any]) -> String? {
        if let hangout = payload["hangoutLink"] as? String {
            return hangout
        }
        let description = payload["description"] as? String ?? ""
        let location = payload["location"] as? String ?? ""
        return MeetingLinkExtractor.extract(description: description, location: location)
    }
}

public enum CalendarSyncEngine {
    public static func sync(
        accounts: [GoogleAccount],
        accessTokenProvider: @escaping (UUID) async throws -> String
    ) async -> [CalendarEventSummary] {
        var events: [CalendarEventSummary] = []

        await withTaskGroup(of: [CalendarEventSummary].self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let token = try await accessTokenProvider(account.id)
                        let payloads = try await CalendarAPIClient.fetchUpcomingEvents(accessToken: token)
                        return payloads.compactMap { CalendarEventParser.parse($0, account: account) }
                    } catch {
                        return []
                    }
                }
            }

            for await accountEvents in group {
                events.append(contentsOf: accountEvents)
            }
        }

        return events.sorted { $0.startDate < $1.startDate }
    }
}

public enum MeetingReminderPlanner {
    public struct Reminder: Sendable, Hashable {
        public var event: CalendarEventSummary
        public var fireDate: Date
        public var kind: Kind

        public enum Kind: String, Sendable {
            case twoMinutes
        }
    }

    public static let reminderLeadTime: TimeInterval = 120
    public static let sameStartTolerance: TimeInterval = 60
    /// Matches the in-app watchdog poll interval so we do not miss the 2-minute window.
    public static let dueWindowTolerance: TimeInterval = 20

    public static func eventsStartingTogether(
        with event: CalendarEventSummary,
        in events: [CalendarEventSummary],
        tolerance: TimeInterval = sameStartTolerance
    ) -> [CalendarEventSummary] {
        events
            .filter { abs($0.startDate.timeIntervalSince(event.startDate)) <= tolerance }
            .sorted { lhs, rhs in
                let emailOrder = lhs.accountEmail.localizedCaseInsensitiveCompare(rhs.accountEmail)
                if emailOrder != .orderedSame {
                    return emailOrder == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    public static func reminders(for events: [CalendarEventSummary], now: Date = Date()) -> [Reminder] {
        var results: [Reminder] = []
        for event in events where event.startDate > now {
            let secondsUntilStart = event.startDate.timeIntervalSince(now)
            let fireDate = event.startDate.addingTimeInterval(-reminderLeadTime)
            if fireDate > now {
                results.append(Reminder(event: event, fireDate: fireDate, kind: .twoMinutes))
            } else if secondsUntilStart <= reminderLeadTime {
                // Meeting starts within 2 minutes — schedule an imminent alert.
                results.append(Reminder(event: event, fireDate: now.addingTimeInterval(5), kind: .twoMinutes))
            }
        }
        return results
    }

    /// Events that should alert right now (about 2 minutes before start).
    public static func dueReminders(for events: [CalendarEventSummary], now: Date = Date()) -> [Reminder] {
        events.compactMap { event in
            guard event.startDate > now else { return nil }
            let secondsUntilStart = event.startDate.timeIntervalSince(now)
            let delta = abs(secondsUntilStart - reminderLeadTime)
            guard delta <= dueWindowTolerance else { return nil }
            return Reminder(event: event, fireDate: now, kind: .twoMinutes)
        }
    }
}
