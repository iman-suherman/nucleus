import Foundation

struct LRCLibLyricsPayload: Sendable {
    var syncedLines: [SyncedLyricLine]
    var plainLines: [String]
    var isSynced: Bool
}

struct LRCLibSearchHit: Sendable {
    var trackName: String
    var artistName: String
    var albumName: String
    var duration: TimeInterval
    var matchedLine: String?
    var score: Double
}

enum LRCLibLyricsClient {
    private struct APIResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    private struct SearchResponse: Decodable {
        let trackName: String?
        let name: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
    }

    static func search(query: String, limit: Int = 10) async throws -> [LRCLibSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]

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
            if http.statusCode == 404 { return [] }
            throw LyricsFetchError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode([SearchResponse].self, from: data)
        let queryTokens = lyricTokens(from: trimmed)

        return decoded
            .filter { $0.instrumental != true }
            .compactMap { row -> LRCLibSearchHit? in
                let track = (row.trackName ?? row.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = (row.artistName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !track.isEmpty, !artist.isEmpty else { return nil }

                let lyrics = row.plainLyrics ?? ""
                let matchedLine = bestMatchingLine(in: lyrics, queryTokens: queryTokens, rawQuery: trimmed)
                let score = lyricsMatchScore(lyrics: lyrics, queryTokens: queryTokens, rawQuery: trimmed, matchedLine: matchedLine)

                return LRCLibSearchHit(
                    trackName: track,
                    artistName: artist,
                    albumName: (row.albumName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    duration: row.duration ?? 0,
                    matchedLine: matchedLine,
                    score: score
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    private static func lyricTokens(from query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private static func bestMatchingLine(in lyrics: String, queryTokens: [String], rawQuery: String) -> String? {
        let lines = lyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let loweredQuery = rawQuery.lowercased()
        if let exact = lines.first(where: { $0.lowercased().contains(loweredQuery) }) {
            return exact
        }

        var best: (line: String, score: Double)?
        for line in lines {
            let lowered = line.lowercased()
            let hits = queryTokens.filter { lowered.contains($0) }.count
            guard hits > 0 else { continue }
            let score = Double(hits) / Double(max(queryTokens.count, 1))
            if best == nil || score > best!.score {
                best = (line, score)
            }
        }
        return best?.line
    }

    private static func lyricsMatchScore(
        lyrics: String,
        queryTokens: [String],
        rawQuery: String,
        matchedLine: String?
    ) -> Double {
        let loweredLyrics = lyrics.lowercased()
        let loweredQuery = rawQuery.lowercased()
        var score = 0.0

        if loweredLyrics.contains(loweredQuery) {
            score += 10
        }

        let tokenHits = queryTokens.filter { loweredLyrics.contains($0) }.count
        score += Double(tokenHits) * 2

        if matchedLine != nil {
            score += 3
        }

        return score
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
