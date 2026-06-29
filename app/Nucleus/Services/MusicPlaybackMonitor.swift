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
    private var isMediaWorkspaceVisible = false
    private var isPollingActive = false

    init() {
        refresh()
        updatePollingState()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func setMediaWorkspaceVisible(_ visible: Bool) {
        isMediaWorkspaceVisible = visible
        updatePollingState()
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
        updatePollingState()
    }

    func refresh() {
        let previousArtwork = nowPlaying.artworkURL

        if let musicKitState = MusicKitNowPlayingReader.fetch() {
            nowPlaying = musicKitState
        } else if let scriptState = MusicAppScriptController.fetchNowPlaying() {
            nowPlaying = scriptState
        } else if nowPlaying.hasContent {
            nowPlaying.isPlaying = false
            nowPlaying.playerState = .stopped
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
        updatePollingState()
    }

    private var shouldPoll: Bool {
        isMediaWorkspaceVisible || nowPlaying.playerState == .playing
    }

    private func updatePollingState() {
        if shouldPoll {
            guard !isPollingActive else { return }
            isPollingActive = true
            scheduleTimer()
        } else {
            guard isPollingActive else { return }
            isPollingActive = false
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func setPollInterval(_ interval: TimeInterval) {
        guard interval != pollInterval else { return }
        pollInterval = interval
        if isPollingActive {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        guard isPollingActive else { return }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }
}
