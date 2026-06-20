import Foundation

struct LRCLibLyricsPayload: Sendable {
    var syncedLines: [SyncedLyricLine]
    var plainLines: [String]
    var isSynced: Bool
}

enum LRCLibLyricsClient {
    private struct APIResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    static func fetch(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async throws -> LRCLibLyricsPayload {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.isEmpty {
            query.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 0 {
            query.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components.queryItems = query

        guard let url = components.url else {
            throw LyricsFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue("Nucleus/1.0 (https://nucleus.suherman.net)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LyricsFetchError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 {
                throw LyricsFetchError.notFound
            }
            throw LyricsFetchError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        if decoded.instrumental == true {
            throw LyricsFetchError.instrumental
        }

        if let synced = decoded.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty {
                return LRCLibLyricsPayload(syncedLines: lines, plainLines: [], isSynced: true)
            }
        }

        if let plain = decoded.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { throw LyricsFetchError.notFound }
            return LRCLibLyricsPayload(syncedLines: [], plainLines: lines, isSynced: false)
        }

        throw LyricsFetchError.notFound
    }
}

enum LyricsFetchError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case notFound
    case instrumental
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequest, .invalidResponse:
            return "Could not load lyrics."
        case .notFound:
            return "No lyrics found for this track."
        case .instrumental:
            return "Instrumental track — no lyrics available."
        case .httpStatus:
            return "Lyrics service unavailable."
        }
    }
}
