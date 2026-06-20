import Combine
import Foundation
import MusicKit
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
    @Published private(set) var musicAccess = MusicAccessSetup.makeSnapshot(
        catalogStatus: .notDetermined,
        automation: .musicAppMissing
    )

    let musicMonitor = MusicPlaybackMonitor()
    let catalogService = MusicCatalogService()
    let localPlayer = LocalMediaPlayerService()

    private var searchTask: Task<Void, Never>?
    private var searchQueueTask: Task<Void, Never>?
    private var searchPlaybackQueue: [MediaSearchResult] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        catalogService.refreshAuthorization()
        refreshMusicAccess()
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
            searchPlaybackQueue = [result]
            searchQueueTask = Task { await playSearchQueue(from: 0) }
            return
        }

        searchPlaybackQueue = Array(searchResults[startIndex...])
        guard !searchPlaybackQueue.isEmpty else { return }

        searchQueueTask = Task {
            await playSearchQueue(from: 0)
        }
    }

    private func playSearchQueue(from startIndex: Int) async {
        playbackSource = .musicApp

        if startIndex == 0,
           await catalogService.playCatalogSongQueue(searchPlaybackQueue) {
            activeSearchResultID = searchPlaybackQueue.first?.id
            if let first = searchPlaybackQueue.first {
                musicMonitor.applyOptimisticNowPlaying(from: first)
            }
            musicMonitor.refresh()
            statusMessage = searchPlaybackQueue.count == 1
                ? "Playing “\(searchPlaybackQueue[0].title)”"
                : "Playing \(searchPlaybackQueue.count) tracks from search"

            if searchPlaybackQueue.count > 1 {
                await waitForMusicKitSearchQueueToFinish(startIndex: 0)
            }
            return
        }

        for index in startIndex..<searchPlaybackQueue.count {
            guard !Task.isCancelled else { return }

            let result = searchPlaybackQueue[index]
            activeSearchResultID = result.id
            musicMonitor.applyOptimisticNowPlaying(from: result)
            await catalogService.play(result)
            musicMonitor.refresh()
            updateSearchPlaybackStatus(for: result, index: index, total: searchPlaybackQueue.count)

            guard index < searchPlaybackQueue.count - 1 else { break }
            await waitForSearchQueueAdvance()
            guard !Task.isCancelled else { return }
        }
    }

    private func waitForMusicKitSearchQueueToFinish(startIndex: Int) async {
        let lastIndex = searchPlaybackQueue.count - 1
        var sawPlaying = false
        var lastTitle = ""

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            musicMonitor.refresh()
            let info = musicMonitor.nowPlaying

            if info.playerState == .playing {
                sawPlaying = true
            }

            if sawPlaying, !info.title.isEmpty, info.title != lastTitle {
                lastTitle = info.title
                if let matchedIndex = searchPlaybackQueue.firstIndex(where: {
                    $0.title.caseInsensitiveCompare(info.title) == .orderedSame
                }) {
                    activeSearchResultID = searchPlaybackQueue[matchedIndex].id
                    updateSearchPlaybackStatus(
                        for: searchPlaybackQueue[matchedIndex],
                        index: matchedIndex,
                        total: searchPlaybackQueue.count
                    )
                }
            }

            guard sawPlaying, hasSearchTrackFinished(info) else { continue }

            let currentIndex = searchPlaybackQueue.firstIndex(where: {
                $0.title.caseInsensitiveCompare(info.title) == .orderedSame
            }) ?? startIndex

            if currentIndex >= lastIndex {
                try? await Task.sleep(nanoseconds: 350_000_000)
                musicMonitor.refresh()
                if hasSearchTrackFinished(musicMonitor.nowPlaying) {
                    return
                }
            } else {
                try? await Task.sleep(nanoseconds: 800_000_000)
                musicMonitor.refresh()
                if musicMonitor.nowPlaying.playerState == .playing {
                    continue
                }
            }
        }
    }

    private func waitForSearchQueueAdvance() async {
        var sawPlaying = false
        var stoppedTicks = 0

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            musicMonitor.refresh()
            let info = musicMonitor.nowPlaying

            if info.playerState == .playing {
                sawPlaying = true
                stoppedTicks = 0
            }

            guard sawPlaying else { continue }

            if hasSearchTrackFinished(info) {
                try? await Task.sleep(nanoseconds: 350_000_000)
                musicMonitor.refresh()
                if hasSearchTrackFinished(musicMonitor.nowPlaying) {
                    return
                }
            }

            if info.playerState == .stopped {
                stoppedTicks += 1
                if stoppedTicks >= 2 {
                    return
                }
            }
        }
    }

    private func hasSearchTrackFinished(_ info: MediaNowPlayingInfo) -> Bool {
        if info.playerState == .stopped {
            return true
        }

        if info.duration > 0,
           info.elapsed >= max(0, info.duration - 1.0),
           info.playerState != .playing {
            return true
        }

        return false
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
        refreshMusicAccess()
        scheduleSearch()
    }

    func refreshMusicAccess() {
        catalogService.refreshAuthorization()
        musicAccess = MusicAccessSetup.makeSnapshot(
            catalogStatus: catalogService.authorizationStatus,
            automation: MusicAppScriptController.probeAutomationAccess()
        )
    }

    func setupMusicAccess() async {
        NucleusLog.music.info("music access setup started (catalog=\(String(describing: self.catalogService.authorizationStatus), privacy: .public))")

        if catalogService.authorizationStatus != .authorized {
            await catalogService.requestAuthorization()
        }

        MusicAppScriptController.requestAutomationAccess()
        refreshMusicAccess()

        NucleusLog.music.info(
            "music access setup finished (catalog=\(String(describing: self.musicAccess.catalogAccess), privacy: .public) automation=\(String(describing: self.musicAccess.musicAutomation), privacy: .public))"
        )

        if musicAccess.isFullyReady {
            statusMessage = "Music access is ready."
        } else if musicAccess.catalogAccess == .denied || musicAccess.musicAutomation == .denied {
            statusMessage = "Enable the remaining permissions in System Settings."
        } else if musicAccess.musicAutomation == .musicAppMissing {
            statusMessage = "Install Music.app to play your library from Nucleus."
        } else {
            statusMessage = "Finish the macOS prompts, then return to Nucleus."
        }
    }

    func openMusicAccessSettings(_ pane: MusicAccessSettingsPane) {
        MusicAccessSetup.openSettings(pane)
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
