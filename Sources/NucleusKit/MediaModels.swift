import Foundation

public enum MediaPlaybackSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case musicApp
    case localPlayer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .musicApp: return "Music App"
        case .localPlayer: return "Nucleus Player"
        }
    }

    public var subtitle: String {
        switch self {
        case .musicApp: return "Control Apple Music via Music.app"
        case .localPlayer: return "Stream local audio over AirPlay"
        }
    }
}

public enum MediaSearchScope: String, Sendable {
    case appleMusicCatalog
    case musicLibrary
    case lyricsMatch
    case semanticSearch
}

public enum MediaSearchKind: String, Codable, Sendable {
    case song
    case album
    case artist
    case playlist
}

public struct MediaSearchResult: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var kind: MediaSearchKind
    public var artworkURL: String?
    /// Why this result matched, e.g. a lyrics line or semantic expansion note.
    public var matchReason: String?

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: MediaSearchKind,
        artworkURL: String? = nil,
        matchReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.artworkURL = artworkURL
        self.matchReason = matchReason
    }
}

public struct MediaShortcut: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var detail: String

    public init(id: UUID = UUID(), name: String, detail: String = "") {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

public struct MediaFavoritePlaylist: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public enum MediaPlayerState: String, Sendable, Equatable {
    case stopped
    case playing
    case paused
}

public struct MediaNowPlayingInfo: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var isPlaying: Bool
    public var playerState: MediaPlayerState
    public var artworkURL: String?
    public var outputDevice: String

    public init(
        title: String = "",
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        isPlaying: Bool = false,
        playerState: MediaPlayerState = .stopped,
        artworkURL: String? = nil,
        outputDevice: String = ""
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.isPlaying = isPlaying
        self.playerState = playerState
        self.artworkURL = artworkURL
        self.outputDevice = outputDevice
    }

    public var hasContent: Bool {
        !title.isEmpty || !artist.isEmpty
    }

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }
}

public enum MediaRepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one

    public var label: String {
        switch self {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }
}
