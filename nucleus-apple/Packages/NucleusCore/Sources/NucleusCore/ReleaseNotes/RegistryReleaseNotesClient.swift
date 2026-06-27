import Foundation

enum RegistryReleaseNotesClient {
    private static let registryBaseURL = URL(string: "https://nucleus-registry.suherman.net")!
    private static let appID = "nucleus-macos"

    static func fetchRelease(for version: String) async -> AppReleaseNotes? {
        let endpoints = [
            registryBaseURL.appendingPathComponent("api/v1/plugins/\(appID)/versions/\(version)"),
            registryBaseURL.appendingPathComponent("api/v1/plugins/\(appID)/versions/latest"),
        ]

        for url in endpoints {
            guard let payload = await fetchPayload(from: url) else { continue }
            if payload.version == version, let release = map(payload) {
                return release
            }
        }
        return nil
    }

    private static func fetchPayload(from url: URL) async -> RegistryVersionPayload? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(RegistryVersionPayload.self, from: data)
        } catch {
            return nil
        }
    }

    private static func map(_ payload: RegistryVersionPayload) -> AppReleaseNotes? {
        guard !payload.version.isEmpty else { return nil }
        return AppReleaseNotes(
            version: payload.version,
            summary: payload.summary,
            releaseNotes: payload.releaseNotes ?? .init()
        )
    }
}

private struct RegistryVersionPayload: Decodable {
    let version: String
    let summary: String?
    let releaseNotes: AppReleaseNotes.Sections?
}
