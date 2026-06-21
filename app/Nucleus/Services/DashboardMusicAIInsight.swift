import Foundation
import NucleusKit

enum DashboardMusicAIInsight {
    struct Track: Equatable {
        let key: String
        let title: String
        let artist: String
        let album: String
    }

    private(set) static var isDashboardVisible = false
    private(set) static var lastAskedTrackKey: String?

    static func setDashboardVisible(_ visible: Bool) {
        isDashboardVisible = visible
    }

    static func track(from info: MediaNowPlayingInfo) -> Track? {
        let title = info.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = info.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = info.album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !artist.isEmpty else { return nil }

        let key = [artist, title, album]
            .map { $0.lowercased() }
            .joined(separator: "|")
        return Track(key: key, title: title, artist: artist, album: album)
    }

    static func curatedQuestion(for track: Track) -> String {
        var songDescriptor = "\"\(track.title)\""
        if !track.album.isEmpty {
            songDescriptor += " from the album \"\(track.album)\""
        }

        if track.artist.isEmpty {
            return "Tell me about the song \(songDescriptor): its background, meaning, and why it stands out."
        }

        return "Tell me about \(songDescriptor) by \(track.artist). Cover the song's background and meaning, and what is notable about the artist."
    }

    static func contextLabel(for track: Track) -> String {
        if track.artist.isEmpty {
            return "Now playing · \"\(track.title)\""
        }
        return "Now playing · \"\(track.title)\" by \(track.artist)"
    }

    static func shouldAutoAsk(for trackKey: String) -> Bool {
        isDashboardVisible && trackKey != lastAskedTrackKey
    }

    static func markAsked(_ trackKey: String) {
        lastAskedTrackKey = trackKey
    }
}
