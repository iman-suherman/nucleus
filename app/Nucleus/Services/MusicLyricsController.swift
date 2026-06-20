import Combine
import Foundation
import NucleusKit

@MainActor
final class MusicLyricsController: ObservableObject {
    @Published private(set) var syncedLines: [SyncedLyricLine] = []
    @Published private(set) var plainLines: [String] = []
    @Published private(set) var isSynced = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var trackDuration: TimeInterval = 0

    private var loadTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var cache: [String: LRCLibLyricsPayload] = [:]
    private var currentTrackKey: String?
    private var cancellables = Set<AnyCancellable>()

    init(mediaController: MediaController = .shared) {
        mediaController.$nowPlaying
            .sink { [weak self] info in
                self?.handleNowPlayingChange(info)
            }
            .store(in: &cancellables)
    }

    deinit {
        tickTimer?.invalidate()
    }

    var activeSyncedLineIndex: Int? {
        SyncedLyricsIndex.activeLineIndex(at: playbackTime, in: syncedLines)
    }

    var activePlainLineIndex: Int? {
        guard !isSynced, !plainLines.isEmpty, trackDuration > 0 else { return nil }
        let progress = min(1, max(0, playbackTime / trackDuration))
        let index = Int(progress * Double(plainLines.count))
        return min(plainLines.count - 1, max(0, index))
    }

    func lineProgress(for lineIndex: Int) -> Double {
        SyncedLyricsIndex.lineProgress(
            at: playbackTime,
            lineIndex: lineIndex,
            lines: syncedLines,
            trackDuration: trackDuration
        )
    }

    private func handleNowPlayingChange(_ info: MediaNowPlayingInfo) {
        trackDuration = info.duration
        playbackTime = info.elapsed

        if info.isPlaying {
            startTickTimer()
        } else {
            stopTickTimer()
        }

        guard info.hasContent else {
            clearLyrics()
            currentTrackKey = nil
            return
        }

        let key = trackKey(for: info)
        guard key != currentTrackKey else { return }

        currentTrackKey = key
        loadLyrics(for: info, key: key)
    }

    private func loadLyrics(for info: MediaNowPlayingInfo, key: String) {
        loadTask?.cancel()

        if let cached = cache[key] {
            apply(cached)
            statusMessage = nil
            return
        }

        syncedLines = []
        plainLines = []
        isSynced = false
        isLoading = true
        statusMessage = nil

        loadTask = Task {
            do {
                let payload = try await LRCLibLyricsClient.fetch(
                    title: info.title,
                    artist: info.artist,
                    album: info.album,
                    duration: info.duration
                )
                guard !Task.isCancelled else { return }
                cache[key] = payload
                apply(payload)
                statusMessage = nil
                NucleusLog.music.info(
                    "lyrics loaded track=\(info.title, privacy: .public) synced=\(payload.isSynced, privacy: .public)"
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                clearLyrics()
                statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                NucleusLog.music.error(
                    "lyrics load failed track=\(info.title, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
            isLoading = false
        }
    }

    private func apply(_ payload: LRCLibLyricsPayload) {
        syncedLines = payload.syncedLines
        plainLines = payload.plainLines
        isSynced = payload.isSynced
    }

    private func clearLyrics() {
        loadTask?.cancel()
        syncedLines = []
        plainLines = []
        isSynced = false
        isLoading = false
        statusMessage = nil
    }

    private func trackKey(for info: MediaNowPlayingInfo) -> String {
        [
            info.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            info.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            info.album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            String(Int(info.duration.rounded())),
        ].joined(separator: "|")
    }

    private func startTickTimer() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let info = MediaController.shared.nowPlaying
                self.playbackTime = info.elapsed
                self.trackDuration = info.duration
                if !info.isPlaying {
                    self.stopTickTimer()
                }
            }
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}
