import Foundation
import MusicKit
import NucleusKit

enum MusicKitNowPlayingReader {
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
}
