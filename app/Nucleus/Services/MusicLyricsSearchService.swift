import Foundation
import MusicKit
import NucleusKit

@MainActor
enum MusicLyricsSearchService {
    static func searchCatalogSongs(query: String, limit: Int = 6) async -> [MediaSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard MusicAuthorization.currentStatus == .authorized else { return [] }

        let hits: [LRCLibSearchHit]
        do {
            hits = try await LRCLibLyricsClient.search(query: trimmed, limit: limit * 3)
        } catch {
            NucleusLog.music.error("lyrics search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        var results: [MediaSearchResult] = []
        var seen = Set<String>()

        for hit in hits where hit.score > 0 {
            guard let song = await resolveSong(for: hit) else { continue }
            let id = song.id.rawValue
            guard !seen.contains(id) else { continue }
            seen.insert(id)

            let reason = matchReason(for: hit)
            results.append(
                MediaSearchResult(
                    id: id,
                    title: song.title,
                    subtitle: song.artistName,
                    kind: .song,
                    artworkURL: song.artwork?.url(width: 120, height: 120)?.absoluteString,
                    matchReason: reason
                )
            )

            if results.count >= limit { break }
        }

        return results
    }

    private static func matchReason(for hit: LRCLibSearchHit) -> String {
        if let line = hit.matchedLine {
            let clipped = line.count > 72 ? String(line.prefix(69)) + "…" : line
            return "Lyrics: “\(clipped)”"
        }
        return "Matched lyrics"
    }

    private static func resolveSong(for hit: LRCLibSearchHit) async -> Song? {
        do {
            var request = MusicCatalogSearchRequest(
                term: "\(hit.trackName) \(hit.artistName)",
                types: [Song.self]
            )
            request.limit = 8
            let response = try await request.response()
            return bestSongMatch(in: response.songs, hit: hit)
        } catch {
            return nil
        }
    }

    private static func bestSongMatch(in songs: MusicItemCollection<Song>, hit: LRCLibSearchHit) -> Song? {
        let targetTrack = normalized(hit.trackName)
        let targetArtist = normalized(hit.artistName)

        for song in songs {
            let songTrack = normalized(song.title)
            let songArtist = normalized(song.artistName)
            if songTrack == targetTrack, songArtist.contains(targetArtist) || targetArtist.contains(songArtist) {
                return song
            }
        }

        for song in songs {
            let songTrack = normalized(song.title)
            let songArtist = normalized(song.artistName)
            if songTrack.contains(targetTrack) || targetTrack.contains(songTrack),
               songArtist.contains(targetArtist) || targetArtist.contains(songArtist) {
                return song
            }
        }

        return songs.first
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
