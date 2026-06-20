import Foundation
import MusicKit
import NucleusKit

enum MusicKitNowPlayingReader {
    /// True when `ApplicationMusicPlayer` is actively playing or paused with a queued track.
    static var isControllingPlayback: Bool {
        let player = ApplicationMusicPlayer.shared
        guard player.queue.currentEntry != nil else { return false }

        switch player.state.playbackStatus {
        case .playing, .paused, .interrupted:
            return true
        case .stopped:
            return false
        @unknown default:
            return false
        }
    }

    static func fetch() -> MediaNowPlayingInfo? {
        let player = ApplicationMusicPlayer.shared
        let playbackStatus = player.state.playbackStatus

        var info = MediaNowPlayingInfo()
        info.elapsed = max(0, player.playbackTime)
        info.isPlaying = playbackStatus == .playing
        info.playerState = playerState(for: playbackStatus)

        if let entry = player.queue.currentEntry {
            info.title = entry.title
            info.artist = entry.subtitle ?? ""
            info.artworkURL = entry.artwork?.url(width: 120, height: 120)?.absoluteString

            if let item = entry.item {
                switch item {
                case .song(let song):
                    info.album = song.albumTitle ?? ""
                    info.duration = song.duration ?? 0
                    if info.artworkURL == nil {
                        info.artworkURL = song.artwork?.url(width: 120, height: 120)?.absoluteString
                    }
                case .musicVideo(let video):
                    info.album = video.albumTitle ?? ""
                    info.duration = video.duration ?? 0
                    if info.artworkURL == nil {
                        info.artworkURL = video.artwork?.url(width: 120, height: 120)?.absoluteString
                    }
                @unknown default:
                    break
                }
            }
        }

        guard info.hasContent else { return nil }

        switch playbackStatus {
        case .stopped:
            return info
        case .playing, .paused, .interrupted:
            return info
        @unknown default:
            return nil
        }
    }

    private static func playerState(for status: MusicPlayer.PlaybackStatus) -> MediaPlayerState {
        switch status {
        case .playing:
            return .playing
        case .paused, .interrupted:
            return .paused
        case .stopped:
            return .stopped
        @unknown default:
            return .stopped
        }
    }

    /// Whether the current MusicKit queue entry has reached the end (or playback stopped).
    static func hasFinishedCurrentEntry() -> Bool {
        let player = ApplicationMusicPlayer.shared
        guard player.queue.currentEntry != nil else { return true }

        switch player.state.playbackStatus {
        case .stopped:
            return true
        case .playing, .paused, .interrupted:
            break
        @unknown default:
            return true
        }

        let elapsed = max(0, player.playbackTime)
        guard let duration = currentEntryDuration(player), duration > 0 else {
            return false
        }

        if elapsed >= duration - 0.35 {
            return true
        }

        return player.state.playbackStatus != .playing && elapsed >= duration - 2.0
    }

    private static func currentEntryDuration(_ player: ApplicationMusicPlayer) -> TimeInterval? {
        guard let item = player.queue.currentEntry?.item else { return nil }
        switch item {
        case .song(let song):
            return song.duration
        case .musicVideo(let video):
            return video.duration
        @unknown default:
            return nil
        }
    }
}
