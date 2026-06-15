import Foundation

struct AppReleaseNotes: Decodable, Equatable {
    struct Sections: Decodable, Equatable {
        var breaking: [String]?
        var introduced: [String]?
        var changed: [String]?
        var updated: [String]?
        var fixed: [String]?
        var removed: [String]?
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let items: [String]
    }

    let version: String
    let summary: String?
    let releaseNotes: Sections

    var sections: [Section] {
        [
            Section(id: "breaking", title: "Important changes", items: releaseNotes.breaking ?? []),
            Section(id: "introduced", title: "What's new", items: releaseNotes.introduced ?? []),
            Section(id: "changed", title: "Improvements", items: releaseNotes.changed ?? []),
            Section(id: "fixed", title: "Fixes", items: releaseNotes.fixed ?? []),
            Section(id: "updated", title: "Under the hood", items: releaseNotes.updated ?? []),
            Section(id: "removed", title: "Removed", items: releaseNotes.removed ?? []),
        ].filter { !$0.items.isEmpty }
    }

    var headline: String {
        summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? summary!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Nucleus \(version) is ready."
    }
}

enum ReleaseNotesLoader {
    private static let lastSeenVersionKey = "nucleus.whatsNew.lastSeenVersion"

    static func shouldPresentWhatsNew(currentVersion: String = AppSettings.currentAppVersion) -> Bool {
        lastSeenVersion() != currentVersion
    }

    static func loadCurrentRelease(currentVersion: String = AppSettings.currentAppVersion) -> AppReleaseNotes? {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let release = try? JSONDecoder().decode(AppReleaseNotes.self, from: data),
              release.version == currentVersion else {
            return fallbackRelease(for: currentVersion)
        }
        return release
    }

    static func markCurrentVersionSeen(currentVersion: String = AppSettings.currentAppVersion) {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenVersionKey)
    }

    private static func lastSeenVersion() -> String? {
        UserDefaults.standard.string(forKey: lastSeenVersionKey)
    }

    private static func fallbackRelease(for version: String) -> AppReleaseNotes? {
        guard shouldPresentWhatsNew(currentVersion: version) else { return nil }
        return AppReleaseNotes(
            version: version,
            summary: "Thanks for updating to Nucleus \(version).",
            releaseNotes: .init()
        )
    }
}
