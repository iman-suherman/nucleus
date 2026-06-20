import Foundation
import NucleusKit

@MainActor
final class MusicPlaybackMonitor: ObservableObject {
    @Published private(set) var nowPlaying = MediaNowPlayingInfo()
    @Published private(set) var volume: Int = 50
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var repeatMode: MediaRepeatMode = .off

    private var refreshTimer: Timer?
    private var pollInterval: TimeInterval = 1.0

    init() {
        refresh()
        startPolling()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func applyOptimisticNowPlaying(from result: MediaSearchResult) {
        nowPlaying = MediaNowPlayingInfo(
            title: result.title,
            artist: result.subtitle,
            album: result.kind == .album ? result.title : "",
            isPlaying: true,
            playerState: .playing,
            artworkURL: result.artworkURL
        )
        setPollInterval(0.5)
    }

    func refresh() {
        let previousArtwork = nowPlaying.artworkURL

        if let musicKitState = MusicKitNowPlayingReader.fetch() {
            nowPlaying = musicKitState
        } else if let scriptState = MusicAppScriptController.fetchNowPlaying() {
            nowPlaying = scriptState
        } else if nowPlaying.isPlaying {
            nowPlaying.playerState = .stopped
            nowPlaying.isPlaying = false
        } else {
            nowPlaying = MediaNowPlayingInfo()
        }

        if nowPlaying.artworkURL == nil {
            nowPlaying.artworkURL = previousArtwork
        }

        if let scriptVolume = MusicAppScriptController.fetchVolume() {
            volume = scriptVolume
        }

        setPollInterval(nowPlaying.playerState == .playing ? 0.5 : 1.0)
    }

    private func startPolling() {
        scheduleTimer()
    }

    private func setPollInterval(_ interval: TimeInterval) {
        guard interval != pollInterval else { return }
        pollInterval = interval
        scheduleTimer()
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}
