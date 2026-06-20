import Foundation
import NucleusKit

@MainActor
final class MusicPlaybackMonitor: ObservableObject {
    @Published private(set) var nowPlaying = MediaNowPlayingInfo()
    @Published private(set) var volume: Int = 50
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var repeatMode: MediaRepeatMode = .off

    private var refreshTimer: Timer?

    init() {
        refresh()
        startPolling()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        if let scriptState = MusicAppScriptController.fetchNowPlaying() {
            nowPlaying = scriptState
        } else {
            nowPlaying = MediaNowPlayingInfo()
        }

        if let scriptVolume = MusicAppScriptController.fetchVolume() {
            volume = scriptVolume
        }
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}
