import Combine
import Foundation
import NucleusKit

@MainActor
final class MediaController: ObservableObject {
    static let shared = MediaController()

    @Published var playbackSource: MediaPlaybackSource = .musicApp
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [MediaSearchResult] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var repeatMode: MediaRepeatMode = .off
    @Published private(set) var nowPlaying = MediaNowPlayingInfo()
    @Published private(set) var activeSearchResultID: String?

    let musicMonitor = MusicPlaybackMonitor()
    let catalogService = MusicCatalogService()
    let localPlayer = LocalMediaPlayerService()

    private var searchTask: Task<Void, Never>?
    private var searchQueueTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        catalogService.refreshAuthorization()
        musicMonitor.$nowPlaying
            .combineLatest(localPlayer.$nowPlaying, $playbackSource)
            .map { music, local, source in
                source == .musicApp ? music : local
            }
            .assign(to: &$nowPlaying)

        musicMonitor.$volume
            .combineLatest(localPlayer.$volume, $playbackSource)
            .sink { [weak self] _, _, _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        localPlayer.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        musicMonitor.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        catalogService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        musicMonitor.$nowPlaying
            .sink { [weak self] info in
                self?.syncActiveSearchResult(with: info)
            }
            .store(in: &cancellables)
    }

    private func syncActiveSearchResult(with info: MediaNowPlayingInfo) {
        guard info.hasContent, !searchResults.isEmpty else { return }
        guard let match = searchResults.first(where: {
            $0.title.caseInsensitiveCompare(info.title) == .orderedSame
                && ($0.subtitle.caseInsensitiveCompare(info.artist) == .orderedSame || info.artist.isEmpty)
        }) else {
            return
        }
        activeSearchResultID = match.id
    }

    var volume: Double {
        switch playbackSource {
        case .musicApp:
            return Double(musicMonitor.volume) / 100
        case .localPlayer:
            return Double(localPlayer.volume)
        }
    }

    var isMusicAppAvailable: Bool {
        MusicAppScriptController.isInstalled()
    }

    func setPlaybackSource(_ source: MediaPlaybackSource) {
        playbackSource = source
    }

    func togglePlayPause() {
        switch playbackSource {
        case .musicApp:
            MusicAppScriptController.playPause()
            musicMonitor.refresh()
        case .localPlayer:
            localPlayer.togglePlayPause()
        }
    }

    func play() {
        switch playbackSource {
        case .musicApp:
            MusicAppScriptController.play()
            musicMonitor.refresh()
        case .localPlayer:
            localPlayer.play()
        }
    }

    func pause() {
        switch playbackSource {
        case .musicApp:
            MusicAppScriptController.pause()
            musicMonitor.refresh()
        case .localPlayer:
            localPlayer.pause()
        }
    }

    func nextTrack() {
        switch playbackSource {
        case .musicApp:
            MusicAppScriptController.nextTrack()
            musicMonitor.refresh()
        case .localPlayer:
            localPlayer.nextInQueue()
        }
    }

    func previousTrack() {
        switch playbackSource {
        case .musicApp:
            MusicAppScriptController.previousTrack()
            musicMonitor.refresh()
        case .localPlayer:
            localPlayer.previousInQueue()
        }
    }

    func setVolume(_ value: Double) {
        let clamped = max(0, min(1, value))
        switch playbackSource {
        case .musicApp:
            MusicAppScriptController.setVolume(Int(clamped * 100))
            musicMonitor.refresh()
        case .localPlayer:
            localPlayer.setVolume(Float(clamped))
        }
    }

    func seek(to progress: Double) {
        guard playbackSource == .localPlayer else { return }
        localPlayer.seek(to: progress)
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        MusicAppScriptController.setShuffleEnabled(shuffleEnabled)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        MusicAppScriptController.setSongRepeat(repeatMode)
    }

    func playPlaylist(named name: String) {
        playbackSource = .musicApp
        MusicAppScriptController.playPlaylist(named: name)
        musicMonitor.refresh()
    }

    func playSearchResult(_ result: MediaSearchResult) async {
        searchQueueTask?.cancel()

        guard let startIndex = searchResults.firstIndex(where: { $0.id == result.id }) else {
            await playSingleSearchResult(result)
            return
        }

        let queue = Array(searchResults[startIndex...])
        guard !queue.isEmpty else { return }

        searchQueueTask = Task {
            await playSearchQueue(queue)
        }
    }

    private func playSingleSearchResult(_ result: MediaSearchResult) async {
        playbackSource = .musicApp
        activeSearchResultID = result.id
        musicMonitor.applyOptimisticNowPlaying(from: result)
        await catalogService.play(result)
        musicMonitor.refresh()
        updateSearchPlaybackStatus(for: result, index: 0, total: 1)
    }

    private func playSearchQueue(_ queue: [MediaSearchResult]) async {
        playbackSource = .musicApp

        if await catalogService.playCatalogSongQueue(queue) {
            activeSearchResultID = queue.first?.id
            if let first = queue.first {
                musicMonitor.applyOptimisticNowPlaying(from: first)
            }
            musicMonitor.refresh()
            statusMessage = queue.count == 1
                ? "Playing “\(queue[0].title)”"
                : "Playing \(queue.count) tracks from search"
            return
        }

        for (index, result) in queue.enumerated() {
            guard !Task.isCancelled else { return }

            activeSearchResultID = result.id
            musicMonitor.applyOptimisticNowPlaying(from: result)
            await catalogService.play(result)
            musicMonitor.refresh()
            updateSearchPlaybackStatus(for: result, index: index, total: queue.count)

            guard index < queue.count - 1 else { break }
            await waitForSearchQueueAdvance()
            guard !Task.isCancelled else { return }
        }
    }

    private func updateSearchPlaybackStatus(for result: MediaSearchResult, index: Int, total: Int) {
        if let error = catalogService.lastError, !error.hasPrefix("Showing your Music library") {
            statusMessage = error
        } else if total > 1 {
            statusMessage = "Playing “\(result.title)” (\(index + 1)/\(total))"
        } else {
            statusMessage = "Playing “\(result.title)”"
        }
    }

    private func waitForSearchQueueAdvance() async {
        var sawPlaying = false

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            musicMonitor.refresh()
            let state = musicMonitor.nowPlaying.playerState

            if state == .playing {
                sawPlaying = true
            } else if sawPlaying && state == .stopped {
                try? await Task.sleep(nanoseconds: 400_000_000)
                musicMonitor.refresh()
                if musicMonitor.nowPlaying.playerState == .stopped {
                    return
                }
            }
        }
    }

    func runShortcut(named name: String) async {
        let result = await ShortcutsRunner.runShortcut(named: name)
        switch result {
        case .success:
            statusMessage = "Ran shortcut “\(name)”."
            musicMonitor.refresh()
        case .failure(let error):
            statusMessage = error.localizedDescription
        }
    }

    func loadLocalFiles(urls: [URL]) {
        playbackSource = .localPlayer
        localPlayer.loadQueue(urls: urls)
        localPlayer.play()
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let results = await catalogService.search(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
            statusMessage = results.isEmpty ? catalogService.lastError : nil
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQueueTask?.cancel()
        activeSearchResultID = nil
        searchQuery = ""
        searchResults = []
        statusMessage = nil
        catalogService.resetSearchState()
    }

    func requestAppleMusicAccess() async {
        await catalogService.requestAuthorization()
        scheduleSearch()
    }

    func reportStatus(_ message: String?) {
        statusMessage = message
    }

    func refreshNowPlaying() {
        musicMonitor.refresh()
    }

    func selectAirPlayDevice(named name: String) {
        guard playbackSource == .musicApp else { return }
        MusicAppScriptController.setAirPlayDevice(named: name)
        musicMonitor.refresh()
        statusMessage = "AirPlay: \(name)"
    }
}
