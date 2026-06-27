import Foundation

public struct AppReleaseNotes: Decodable, Equatable, Sendable {
    public struct Sections: Decodable, Equatable, Sendable {
        public var breaking: [String]?
        public var introduced: [String]?
        public var changed: [String]?
        public var updated: [String]?
        public var fixed: [String]?
        public var removed: [String]?

        public init(
            breaking: [String]? = nil,
            introduced: [String]? = nil,
            changed: [String]? = nil,
            updated: [String]? = nil,
            fixed: [String]? = nil,
            removed: [String]? = nil
        ) {
            self.breaking = breaking
            self.introduced = introduced
            self.changed = changed
            self.updated = updated
            self.fixed = fixed
            self.removed = removed
        }
    }

    public struct Section: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let items: [String]

        public init(id: String, title: String, items: [String]) {
            self.id = id
            self.title = title
            self.items = items
        }
    }

    public let version: String
    public let summary: String?
    public let releaseNotes: Sections

    public init(version: String, summary: String?, releaseNotes: Sections) {
        self.version = version
        self.summary = summary
        self.releaseNotes = releaseNotes
    }

    public var sections: [Section] {
        [
            Section(id: "breaking", title: "Important changes", items: releaseNotes.breaking ?? []),
            Section(id: "introduced", title: "What's new", items: releaseNotes.introduced ?? []),
            Section(id: "changed", title: "Improvements", items: releaseNotes.changed ?? []),
            Section(id: "fixed", title: "Fixes", items: releaseNotes.fixed ?? []),
            Section(id: "updated", title: "Under the hood", items: releaseNotes.updated ?? []),
            Section(id: "removed", title: "Removed", items: releaseNotes.removed ?? []),
        ].filter { !$0.items.isEmpty }
    }

    public var headline: String {
        summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? summary!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Nucleus \(version) is ready."
    }

    var hasDetailedNotes: Bool {
        !sections.isEmpty
    }
}
