import Foundation
import NucleusKit

public enum CalendarJunkFilter {
    private static let chromeTitlePatterns: [String] = [
        #"^add a working location$"#,
        #"^add working location$"#,
        #"^add location$"#,
        #"^change working location$"#,
        #"^change work location$"#,
        #"^add title$"#,
        #"^create event$"#,
        #"^create meeting$"#,
        #"^create task$"#,
        #"^add note$"#,
        #"^more options$"#,
        #"^join with google meet$"#,
    ]

    public static func isCalendarChromeTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        var candidates = [trimmed]
        if let comma = trimmed.firstIndex(of: ",") {
            let prefix = String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                candidates.append(prefix)
            }
        }

        return candidates.contains { isCalendarChromeSegment($0) }
    }

    private static func isCalendarChromeSegment(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("add a ") && lower.contains("location") { return true }
        if lower.hasPrefix("add ") && lower.hasSuffix(" location") { return true }
        if lower.hasPrefix("change ") && lower.contains("location") { return true }
        if lower.hasPrefix("working location") { return true }
        return chromeTitlePatterns.contains { pattern in
            lower.range(of: pattern, options: .regularExpression) != nil
        }
    }

    public static func isLikelyMeeting(_ event: CalendarEventSummary) -> Bool {
        !isCalendarChromeTitle(event.title)
    }
}
