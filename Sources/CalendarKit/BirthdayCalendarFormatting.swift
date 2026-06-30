import Foundation

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
}
