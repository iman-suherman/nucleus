import Foundation

public enum ReleaseNotesLoader {
    private static let lastSeenVersionKey = "nucleus.whatsNew.lastSeenVersion"

    public static func shouldPresentWhatsNew(currentVersion: String = NucleusAppVersion.current) -> Bool {
        lastSeenVersion() != currentVersion
    }

    public static func loadCurrentRelease(currentVersion: String = NucleusAppVersion.current) -> AppReleaseNotes? {
        loadBundledRelease(for: currentVersion) ?? fallbackRelease(for: currentVersion)
    }

    public static func loadCurrentReleaseAsync(
        currentVersion: String = NucleusAppVersion.current
    ) async -> AppReleaseNotes? {
        if let bundled = loadBundledRelease(for: currentVersion), bundled.hasDetailedNotes {
            return bundled
        }

        if let remote = await RegistryReleaseNotesClient.fetchRelease(for: currentVersion),
           remote.hasDetailedNotes {
            return remote
        }

        if let bundled = loadBundledRelease(for: currentVersion) {
            return bundled
        }

        return fallbackRelease(for: currentVersion)
    }

    public static func markCurrentVersionSeen(currentVersion: String = NucleusAppVersion.current) {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenVersionKey)
    }

    private static func lastSeenVersion() -> String? {
        UserDefaults.standard.string(forKey: lastSeenVersionKey)
    }

    private static func loadBundledRelease(for version: String) -> AppReleaseNotes? {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let release = try? JSONDecoder().decode(AppReleaseNotes.self, from: data),
              release.version == version else {
            return nil
        }
        return release
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
