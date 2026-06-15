import Foundation
import NucleusKit

public enum CalendarWebEventParser {
    public static func parse(labels: [String], account: GoogleAccount, now: Date = Date()) -> [CalendarEventSummary] {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        var events: [CalendarEventSummary] = []

        for (index, label) in labels.enumerated() {
            guard let parsed = parseLabel(label, now: now, horizon: horizon) else { continue }
            events.append(
                CalendarEventSummary(
                    id: "\(account.id.uuidString)-web-\(index)-\(parsed.title.hashValue)",
                    accountID: account.id,
                    title: parsed.title,
                    startDate: parsed.startDate,
                    endDate: parsed.endDate,
                    location: parsed.location,
                    meetingLink: parsed.meetingLink,
                    accountEmail: account.email
                )
            )
        }

        return events.sorted { $0.startDate < $1.startDate }
    }

    private struct ParsedEvent {
        var title: String
        var startDate: Date
        var endDate: Date
        var location: String = ""
        var meetingLink: String?
    }

    private static func parseLabel(_ label: String, now: Date, horizon: Date) -> ParsedEvent? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let timePattern = #"^(.+?),\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*[–\-]\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#
        guard let regex = try? NSRegularExpression(pattern: timePattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let titleRange = Range(match.range(at: 1), in: trimmed),
              let startRange = Range(match.range(at: 2), in: trimmed),
              let endRange = Range(match.range(at: 3), in: trimmed) else {
            return nil
        }

        let title = String(trimmed[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let startText = String(trimmed[startRange])
        let endText = String(trimmed[endRange])
        let dayDate = parseDayDate(in: trimmed, reference: now)
        guard let startDate = combine(day: dayDate, time: startText),
              let endDate = combine(day: dayDate, time: endText) else { return nil }
        guard endDate > now, startDate <= horizon else { return nil }
        return ParsedEvent(title: title, startDate: startDate, endDate: endDate)
    }

    private static func parseDayDate(in label: String, reference: Date) -> Date {
        let calendar = Calendar.current
        if label.localizedCaseInsensitiveContains("tomorrow"),
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)) {
            return tomorrow
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEEE, MMMM d", "EEEE, d MMMM", "MMMM d, yyyy", "d MMMM yyyy"] {
            formatter.dateFormat = format
            for part in label.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
                if let date = formatter.date(from: part) {
                    return calendar.startOfDay(for: date)
                }
            }
        }

        for weekday in formatter.weekdaySymbols {
            if label.localizedCaseInsensitiveContains(weekday),
               let date = calendar.nextDate(
                after: calendar.date(byAdding: .day, value: -1, to: reference) ?? reference,
                matching: DateComponents(weekday: formatter.weekdaySymbols.firstIndex(of: weekday)! + 1),
                matchingPolicy: .nextTimePreservingSmallerComponents
               ) {
                return calendar.startOfDay(for: date)
            }
        }

        return calendar.startOfDay(for: reference)
    }

    private static func combine(day: Date, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let normalized = time.replacingOccurrences(of: " ", with: "").lowercased()
        for format in ["h:mma", "ha", "H:mm"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: normalized) {
                let calendar = Calendar.current
                let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
                let timeParts = calendar.dateComponents([.hour, .minute], from: parsed)
                return calendar.date(from: DateComponents(
                    year: dayParts.year,
                    month: dayParts.month,
                    day: dayParts.day,
                    hour: timeParts.hour,
                    minute: timeParts.minute
                ))
            }
        }
        return nil
    }
}
