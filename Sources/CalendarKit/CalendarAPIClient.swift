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
        guard let id = payload["id"] as? String else { return nil }
        let title = payload["summary"] as? String ?? "(Untitled meeting)"
        let location = payload["location"] as? String ?? ""

        let startDate = parseEventDate(payload["start"] as? [String: Any], isEnd: false) ?? Date()
        let endDate = parseEventDate(payload["end"] as? [String: Any], isEnd: true)
            ?? startDate.addingTimeInterval(3600)

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
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateTime) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateTime)
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

    private static func extractMeetingLink(from payload: [String: Any]) -> String? {
        if let hangout = payload["hangoutLink"] as? String {
            return hangout
        }
        if let description = payload["description"] as? String {
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
        }
        if let location = payload["location"] as? String, location.hasPrefix("http") {
            return location
        }
        return nil
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
            case tenMinutes
            case oneMinute
            case starting
        }
    }

    public static func reminders(for events: [CalendarEventSummary], now: Date = Date()) -> [Reminder] {
        var results: [Reminder] = []
        for event in events where event.startDate > now {
            let tenMinuteDate = event.startDate.addingTimeInterval(-600)
            let oneMinuteDate = event.startDate.addingTimeInterval(-60)

            if tenMinuteDate > now {
                results.append(Reminder(event: event, fireDate: tenMinuteDate, kind: .tenMinutes))
            }
            if oneMinuteDate > now {
                results.append(Reminder(event: event, fireDate: oneMinuteDate, kind: .oneMinute))
            }
            results.append(Reminder(event: event, fireDate: event.startDate, kind: .starting))
        }
        return results
    }
}
