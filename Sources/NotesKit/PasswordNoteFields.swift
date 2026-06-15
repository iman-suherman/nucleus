import Foundation
import NucleusKit

public struct PasswordNoteFields: Equatable, Sendable {
    public var name: String
    public var url: String
    public var username: String
    public var email: String
    public var password: String

    public init(
        name: String = "",
        url: String = "",
        username: String = "",
        email: String = "",
        password: String = ""
    ) {
        self.name = name
        self.url = url
        self.username = username
        self.email = email
        self.password = password
    }

    public static func empty(name: String = "New Entry") -> PasswordNoteFields {
        PasswordNoteFields(name: name)
    }

    public func markdown() -> String {
        """
        # \(name)

        url: \(url)
        username: \(username)
        email: \(email)
        password: \(password)
        """
    }

    public static func parse(from markdown: String, fallbackTitle: String) -> PasswordNoteFields {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let name = NotesMarkdown.title(from: markdown, fallback: fallbackTitle)

        return PasswordNoteFields(
            name: name,
            url: fieldValue(in: lines, keys: ["url", "URL"]),
            username: fieldValue(
                in: lines,
                keys: ["username", "Username", "Username / ID"]
            ),
            email: fieldValue(in: lines, keys: ["email", "Email"]),
            password: fieldValue(
                in: lines,
                keys: ["password", "Password", "Secret"]
            )
        )
    }

    private static func fieldValue(in lines: [String], keys: [String]) -> String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) else { continue }

            return String(trimmed[trimmed.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}
