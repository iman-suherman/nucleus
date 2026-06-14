import Foundation
import NucleusKit

public enum ClipboardTagger {
    public static func inferTags(from content: String) -> [String] {
        let lowered = content.lowercased()
        var tags: [String] = []

        let keywords: [(String, String)] = [
            ("docker", "docker"),
            ("kubectl", "kubernetes"),
            ("terraform", "terraform"),
            ("jira", "jira"),
            ("github.com", "github"),
            ("meet.google.com", "meeting"),
            ("zoom.us", "meeting"),
            ("teams.microsoft.com", "meeting"),
        ]

        for (needle, tag) in keywords where lowered.contains(needle) {
            tags.append(tag)
        }

        if content.hasPrefix("http://") || content.hasPrefix("https://") {
            tags.append("url")
        }
        if content.contains("```") || content.contains("func ") || content.contains("class ") {
            tags.append("code")
        }

        return Array(Set(tags)).sorted()
    }
}

public enum ClipboardContentClassifier {
    public static func classify(_ content: String) -> String {
        if content.hasPrefix("http://") || content.hasPrefix("https://") {
            return "url"
        }
        if content.contains("$ ") || content.contains("kubectl") || content.contains("npm ") {
            return "command"
        }
        if content.contains("```") {
            return "code"
        }
        return "text"
    }
}

public struct ClipboardCapture: Sendable {
    public var content: String
    public var sourceApplication: String
    public var capturedAt: Date

    public init(content: String, sourceApplication: String, capturedAt: Date = Date()) {
        self.content = content
        self.sourceApplication = sourceApplication
        self.capturedAt = capturedAt
    }

    public func asEntry() -> ClipboardEntry {
        ClipboardEntry(
            content: content,
            contentType: ClipboardContentClassifier.classify(content),
            sourceApplication: sourceApplication,
            tags: ClipboardTagger.inferTags(from: content),
            isPinned: false,
            capturedAt: capturedAt
        )
    }
}

public enum ClipboardSearch {
    public static func rank(_ entries: [ClipboardEntry], query: String) -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }

        let lowered = trimmed.lowercased()
        return entries
            .filter {
                $0.content.lowercased().contains(lowered)
                    || $0.sourceApplication.lowercased().contains(lowered)
                    || $0.tags.contains { $0.contains(lowered) }
            }
            .sorted { lhs, rhs in
                let lhsScore = score(lhs, query: lowered)
                let rhsScore = score(rhs, query: lowered)
                if lhsScore == rhsScore {
                    return lhs.capturedAt > rhs.capturedAt
                }
                return lhsScore > rhsScore
            }
    }

    private static func score(_ entry: ClipboardEntry, query: String) -> Int {
        var value = 0
        if entry.content.lowercased().contains(query) { value += 3 }
        if entry.tags.contains(where: { $0.contains(query) }) { value += 2 }
        if entry.sourceApplication.lowercased().contains(query) { value += 1 }
        if entry.isPinned { value += 1 }
        return value
    }
}
