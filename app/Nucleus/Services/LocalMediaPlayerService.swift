import AVFoundation
import Foundation
import NucleusKit

@MainActor
final class LocalMediaPlayerService: ObservableObject {
    @Published private(set) var nowPlaying = MediaNowPlayingInfo()
    @Published private(set) var volume: Float = 0.8
    @Published private(set) var queue: [URL] = []
    @Published private(set) var currentURL: URL?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        stopObserving()
        currentURL = url
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.volume = volume
        observePlayer()
        nowPlaying = MediaNowPlayingInfo(
            title: url.deletingPathExtension().lastPathComponent,
            artist: "Local File",
            album: url.deletingLastPathComponent().lastPathComponent,
            isPlaying: false,
            outputDevice: "This Mac"
        )
    }

    func loadQueue(urls: [URL], startingAt index: Int = 0) {
        queue = urls
        guard urls.indices.contains(index) else { return }
        load(url: urls[index])
    }

    func play() {
        player?.play()
        refreshState()
    }

    func pause() {
        player?.pause()
        refreshState()
    }

    func togglePlayPause() {
        if nowPlaying.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to progress: Double) {
        guard let player, nowPlaying.duration > 0 else { return }
        let seconds = nowPlaying.duration * progress
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        refreshState()
    }

    func setVolume(_ value: Float) {
        volume = max(0, min(1, value))
        player?.volume = volume
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        refreshState()
    }

    func nextInQueue() {
        guard let currentURL, let index = queue.firstIndex(of: currentURL), index + 1 < queue.count else { return }
        load(url: queue[index + 1])
        play()
    }

    func previousInQueue() {
        guard let currentURL, let index = queue.firstIndex(of: currentURL) else { return }
        if nowPlaying.elapsed > 3, let player {
            player.seek(to: .zero)
            refreshState()
            return
        }
        guard index > 0 else { return }
        load(url: queue[index - 1])
        play()
    }

    private func observePlayer() {
        guard let player else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshState()
            }
        }

        statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard item.status == .readyToPlay else { return }
                self?.refreshDuration()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.nextInQueue()
            }
        }
    }

    private func refreshDuration() {
        guard let item = player?.currentItem else { return }
        let seconds = item.duration.seconds
        guard seconds.isFinite, seconds > 0 else { return }
        nowPlaying.duration = seconds
    }

    private func refreshState() {
        guard let player else {
            nowPlaying.isPlaying = false
            return
        }

        let current = player.currentTime().seconds
        nowPlaying.elapsed = current.isFinite ? max(0, current) : 0
        nowPlaying.isPlaying = player.rate > 0
        nowPlaying.playerState = player.rate > 0 ? .playing : .paused
        refreshDuration()
    }

    private func stopObserving() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }
}
