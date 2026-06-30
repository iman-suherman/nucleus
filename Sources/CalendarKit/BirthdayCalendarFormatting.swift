import Foundation
import NucleusKit

public enum BirthdayCalendarFormatting {
    public static func displayName(from title: String) -> String {
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return title }

        let suffixes = [
            "'s birthday",
            "’s birthday",
            " birthday",
        ]
        for suffix in suffixes {
            if trimmed.lowercased().hasSuffix(suffix) {
                trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return trimmed.isEmpty ? title : trimmed
    }

    public static func detailTooltip(for birthday: CalendarEventSummary) -> String {
        let name = displayName(from: birthday.title)
        let date = detailDateFormatter.string(from: birthday.startDate)
        var lines = [name, date]
        if !birthday.accountEmail.isEmpty {
            lines.append(birthday.accountEmail)
        }
        if birthday.title != name {
            lines.append(birthday.title)
        }
        return lines.joined(separator: "\n")
    }

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
}
