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
        if ClipboardPasswordAnalyzer.analyze(content) != nil {
            tags.append("password")
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

        let indexed = entries.map(SearchableClipboardEntry.init)
        let lowered = trimmed.lowercased()
        let tokens = lowered
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        let scored = indexed.compactMap { item -> (ClipboardEntry, Int)? in
            let score = lexicalScore(item, query: lowered, tokens: tokens)
            return score > 0 ? (item.entry, score) : nil
        }

        guard !scored.isEmpty else { return [] }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.capturedAt > rhs.0.capturedAt
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private static func lexicalScore(
        _ item: SearchableClipboardEntry,
        query: String,
        tokens: [String]
    ) -> Int {
        var score = 0

        if item.normalizedContent.contains(query) {
            score += 100
        } else if !tokens.isEmpty, tokens.allSatisfy({ item.normalizedContent.contains($0) }) {
            score += 80
        } else if tokens.contains(where: { item.normalizedContent.contains($0) }) {
            score += 40
        }

        if item.normalizedTags.contains(query) {
            score += 50
        } else if tokens.contains(where: { item.normalizedTags.contains($0) }) {
            score += 25
        }

        if item.normalizedSource.contains(query) {
            score += 25
        } else if tokens.contains(where: { item.normalizedSource.contains($0) }) {
            score += 15
        }

        if item.entry.isPinned {
            score += 10
        }

        return score
    }
}
