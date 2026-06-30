import Foundation

public enum MeetingLinkExtractor {
    private static let patterns = [
        "https://meet\\.google\\.com/[a-z0-9-]+",
        "https://[a-z0-9.-]+\\.zoom\\.us/j/[0-9?=&]+",
        "https://teams\\.microsoft\\.com/l/meetup-join/[^\\s]+",
        "https://teams\\.live\\.com/meet/[^\\s]+",
        "https://[a-z0-9.-]+\\.webex\\.com/[^\\s]+",
        "https://whereby\\.com/[^\\s]+",
    ]

    public static func extract(
        conferenceURL: URL? = nil,
        url: URL? = nil,
        description: String = "",
        location: String = ""
    ) -> String? {
        if let conferenceURL {
            return conferenceURL.absoluteString
        }
        if let url, isLikelyMeetingLink(url.absoluteString) {
            return url.absoluteString
        }
        if let fromLocation = firstHTTPURL(in: location) {
            return fromLocation
        }
        return firstMatchingPattern(in: description)
    }

    public static func extract(description: String, location: String) -> String? {
        extract(conferenceURL: nil, url: nil, description: description, location: location)
    }

    private static func isLikelyMeetingLink(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http") || trimmed.hasPrefix("zoommtg://") else { return false }
        if firstMatchingPattern(in: trimmed) != nil { return true }
        let lowered = trimmed.lowercased()
        return lowered.contains("meet.google.com")
            || lowered.contains("zoom.us")
            || lowered.contains("teams.microsoft.com")
            || lowered.contains("teams.live.com")
            || lowered.contains("webex.com")
    }

    private static func firstHTTPURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http") else { return nil }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    private static func firstMatchingPattern(in text: String) -> String? {
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return String(text[range])
            }
        }
        return nil
    }
}
