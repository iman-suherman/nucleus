import Foundation
import NucleusKit

public enum CalendarWebEventParser {
    public struct Entry: Sendable, Codable {
        public let label: String
        public let start: String?
        public let end: String?

        public init(label: String, start: String? = nil, end: String? = nil) {
            self.label = label
            self.start = start
            self.end = end
        }
    }

    public static func parse(labels: [String], account: GoogleAccount, now: Date = Date()) -> [CalendarEventSummary] {
        parse(
            entries: labels.map { Entry(label: $0) },
            account: account,
            now: now
        )
    }

    public static func parse(entries: [Entry], account: GoogleAccount, now: Date = Date()) -> [CalendarEventSummary] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now)) ?? now
        var events: [CalendarEventSummary] = []
        var seen = Set<String>()

        for (index, entry) in entries.enumerated() {
            guard let parsed = parseEntry(entry, now: now, horizon: horizon) else { continue }
            let key = "\(parsed.title.lowercased())-\(Int(parsed.startDate.timeIntervalSince1970 / 60))"
            guard seen.insert(key).inserted else { continue }
            events.append(
                CalendarEventSummary(
                    id: "\(account.id.uuidString)-web-\(index)-\(parsed.title.hashValue)-\(Int(parsed.startDate.timeIntervalSince1970))",
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

    private static let timeRangePattern =
        #"(?i)(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:–|-|—|to)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#

    private static func parseEntry(_ entry: Entry, now: Date, horizon: Date) -> ParsedEvent? {
        if let start = entry.start?.trimmingCharacters(in: .whitespacesAndNewlines),
           let end = entry.end?.trimmingCharacters(in: .whitespacesAndNewlines),
           !start.isEmpty,
           !end.isEmpty {
            let dayDate = parseDayDate(in: entry.label, reference: now)
            if let startDate = combine(day: dayDate, time: start),
               let endDate = combine(day: dayDate, time: end),
               endDate > now,
               startDate < horizon {
                let title = extractTitle(from: entry.label, beforeTime: start)
                return ParsedEvent(title: title, startDate: startDate, endDate: endDate)
            }
        }

        return parseLabel(entry.label, now: now, horizon: horizon)
    }

    private static func parseLabel(_ label: String, now: Date, horizon: Date) -> ParsedEvent? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(pattern: timeRangePattern, options: []),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let startRange = Range(match.range(at: 1), in: trimmed),
              let endRange = Range(match.range(at: 2), in: trimmed) else {
            return parseAllDayLabel(trimmed, now: now, horizon: horizon)
        }

        let startText = String(trimmed[startRange])
        let endText = String(trimmed[endRange])
        let title = extractTitle(from: trimmed, beforeTime: startText)
        let dayDate = parseDayDate(in: trimmed, reference: now)
        guard let startDate = combine(day: dayDate, time: startText),
              let endDate = combine(day: dayDate, time: endText) else { return nil }
        guard endDate > now, startDate < horizon else { return nil }
        return ParsedEvent(title: title, startDate: startDate, endDate: endDate)
    }

    private static func parseAllDayLabel(_ label: String, now: Date, horizon: Date) -> ParsedEvent? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        let title = extractAllDayTitle(from: trimmed)
        guard !title.isEmpty else { return nil }

        let dayDate = parseDayDate(in: trimmed, reference: now)
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: dayDate)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { return nil }
        guard endDate > now, startDate < horizon else { return nil }
        return ParsedEvent(title: title, startDate: startDate, endDate: endDate)
    }

    private static func extractAllDayTitle(from label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = trimmed.firstIndex(of: ",") {
            return String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func extractTitle(from label: String, beforeTime startText: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: startText, options: [.caseInsensitive]) {
            let prefix = String(trimmed[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            if !prefix.isEmpty {
                if let first = prefix.split(separator: ",").first {
                    let title = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        return title
                    }
                }
                return prefix
            }
        }

        if let comma = trimmed.firstIndex(of: ",") {
            return String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func parseDayDate(in label: String, reference: Date) -> Date {
        let calendar = Calendar.current
        let lowercased = label.lowercased()

        if lowercased.contains("today") {
            return calendar.startOfDay(for: reference)
        }

        if lowercased.contains("tomorrow"),
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)) {
            return tomorrow
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEEE, MMMM d, yyyy",
            "EEEE, MMMM d",
            "EEEE, d MMMM yyyy",
            "EEEE, d MMMM",
            "MMMM d, yyyy",
            "MMMM d",
            "d MMMM yyyy",
            "d MMMM",
            "d MMM yyyy",
            "d MMM",
            "MMM d, yyyy",
            "MMM d",
        ]

        for format in formats {
            formatter.dateFormat = format
            for part in label.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
                if let date = formatter.date(from: part) {
                    return normalizedDayDate(from: date, format: format, reference: reference)
                }
            }
            if let date = formatter.date(from: label) {
                return normalizedDayDate(from: date, format: format, reference: reference)
            }
        }

        for weekday in formatter.weekdaySymbols {
            if label.localizedCaseInsensitiveContains(weekday),
               let index = formatter.weekdaySymbols.firstIndex(of: weekday),
               let date = calendar.nextDate(
                after: calendar.date(byAdding: .day, value: -1, to: reference) ?? reference,
                matching: DateComponents(weekday: index + 1),
                matchingPolicy: .nextTimePreservingSmallerComponents
               ) {
                return calendar.startOfDay(for: date)
            }
        }

        return calendar.startOfDay(for: reference)
    }

    private static func normalizedDayDate(from parsed: Date, format: String, reference: Date) -> Date {
        let calendar = Calendar.current
        if format.contains("yyyy") {
            return calendar.startOfDay(for: parsed)
        }

        var components = calendar.dateComponents([.month, .day], from: parsed)
        components.year = calendar.component(.year, from: reference)
        guard var candidate = calendar.date(from: components) else {
            return calendar.startOfDay(for: reference)
        }

        let referenceDay = calendar.startOfDay(for: reference)
        if candidate < calendar.date(byAdding: .day, value: -180, to: referenceDay)! {
            components.year = (components.year ?? 0) + 1
            candidate = calendar.date(from: components) ?? candidate
        } else if candidate > calendar.date(byAdding: .day, value: 180, to: referenceDay)! {
            components.year = (components.year ?? 0) - 1
            candidate = calendar.date(from: components) ?? candidate
        }

        return calendar.startOfDay(for: candidate)
    }

    private static func combine(day: Date, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let normalized = time
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()

        for format in ["h:mma", "hh:mma", "ha", "hha", "H:mm", "HH:mm"] {
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
