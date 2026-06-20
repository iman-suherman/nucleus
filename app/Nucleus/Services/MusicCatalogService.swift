import Foundation
import MusicKit
import NucleusKit

@MainActor
final class MusicCatalogService: ObservableObject {
    @Published private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published private(set) var isSearching = false
    @Published private(set) var lastError: String?
    @Published private(set) var searchScope: MediaSearchScope?

    func refreshAuthorization() {
        authorizationStatus = MusicAuthorization.currentStatus
    }

    func requestAuthorization() async {
        authorizationStatus = await MusicAuthorization.request()
    }

    func resetSearchState() {
        lastError = nil
        searchScope = nil
    }

    func search(query: String) async -> [MediaSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = nil
            searchScope = nil
            return []
        }

        isSearching = true
        defer { isSearching = false }

        var catalogError: String?
        if authorizationStatus != .authorized {
            await requestAuthorization()
        }

        if authorizationStatus == .authorized {
            do {
                var request = MusicCatalogSearchRequest(
                    term: trimmed,
                    types: [Song.self, Album.self, Artist.self, Playlist.self]
                )
                request.limit = 12
                let response = try await request.response()
                let results = mapResults(response)
                if !results.isEmpty {
                    lastError = nil
                    searchScope = .appleMusicCatalog
                    return results
                }
                catalogError = "No Apple Music catalog matches."
            } catch {
                catalogError = error.localizedDescription
            }
        } else if authorizationStatus == .denied {
            catalogError = "Apple Music access denied in System Settings."
        }

        let librarySearch = MusicAppScriptController.searchLibrary(query: trimmed)
        if !librarySearch.results.isEmpty {
            searchScope = .musicLibrary
            if let catalogError {
                lastError = "Showing your Music library. Catalog: \(catalogError)"
            } else {
                lastError = nil
            }
            return librarySearch.results
        }

        searchScope = nil
        if let catalogError {
            lastError = "\(catalogError) \(librarySearch.error ?? "")"
        } else {
            lastError = librarySearch.error
        }
        return []
    }

    func play(_ result: MediaSearchResult) async {
        if result.id.hasPrefix("library-") {
            playViaMusicApp(result)
            return
        }

        guard authorizationStatus == .authorized else {
            lastError = "Allow Apple Music access to play catalog results."
            playViaMusicApp(result)
            return
        }

        do {
            switch result.kind {
            case .song:
                try await playCatalogSong(id: result.id)
            case .album:
                try await playCatalogAlbum(id: result.id)
            case .playlist:
                try await playCatalogPlaylist(id: result.id)
            case .artist:
                try await playCatalogArtist(id: result.id)
            }
            lastError = nil
            NucleusLog.music.info("catalog play started title=\(result.title, privacy: .public) kind=\(result.kind.rawValue, privacy: .public)")
        } catch {
            lastError = "Could not play via Apple Music (\(error.localizedDescription)). Trying Music app…"
            NucleusLog.music.error("catalog play failed title=\(result.title, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            playViaMusicApp(result)
        }
    }

    func playCatalogSongQueue(_ results: [MediaSearchResult]) async -> Bool {
        let songs = results.filter { $0.kind == .song && !$0.id.hasPrefix("library-") }
        guard songs.count == results.count, !songs.isEmpty else { return false }

        if authorizationStatus != .authorized {
            await requestAuthorization()
        }
        guard authorizationStatus == .authorized else { return false }

        do {
            var loadedSongs: [Song] = []
            for result in songs {
                loadedSongs.append(try await catalogSong(id: result.id))
            }
            guard !loadedSongs.isEmpty else { return false }

            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: loadedSongs, startingAt: loadedSongs[0])
            try await player.play()
            lastError = nil
            return true
        } catch {
            lastError = "Could not queue catalog songs (\(error.localizedDescription))."
            return false
        }
    }

    private func playViaMusicApp(_ result: MediaSearchResult) {
        switch result.kind {
        case .song:
            MusicAppScriptController.playTrack(named: result.title, artist: result.subtitle.nilIfEmpty)
        case .playlist:
            MusicAppScriptController.playPlaylist(named: result.title)
        case .album:
            MusicAppScriptController.playAlbum(named: result.title, artist: result.subtitle.nilIfEmpty)
        case .artist:
            MusicAppScriptController.playTrack(named: result.title)
        }
    }

    private func playCatalogSong(id: String) async throws {
        let song = try await catalogSong(id: id)
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: [song], startingAt: song)
        try await player.play()
    }

    private func playCatalogAlbum(id: String) async throws {
        let album = try await catalogAlbum(id: id)
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: [album], startingAt: album)
        try await player.play()
    }

    private func playCatalogPlaylist(id: String) async throws {
        let playlist = try await catalogPlaylist(id: id)
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: [playlist])
        try await player.play()
    }

    private func playCatalogArtist(id: String) async throws {
        let artist = try await catalogArtist(id: id)
        var request = MusicCatalogSearchRequest(term: artist.name, types: [Song.self])
        request.limit = 25
        let response = try await request.response()
        guard let song = response.songs.first else {
            throw CatalogPlaybackError.itemNotFound
        }
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: Array(response.songs), startingAt: song)
        try await player.play()
    }

    private func catalogSong(id: String) async throws -> Song {
        let itemID = MusicItemID(rawValue: id)
        var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
        let response = try await request.response()
        guard let song = response.items.first else {
            throw CatalogPlaybackError.itemNotFound
        }
        return song
    }

    private func catalogAlbum(id: String) async throws -> Album {
        let itemID = MusicItemID(rawValue: id)
        var request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: itemID)
        let response = try await request.response()
        guard let album = response.items.first else {
            throw CatalogPlaybackError.itemNotFound
        }
        return album
    }

    private func catalogPlaylist(id: String) async throws -> Playlist {
        let itemID = MusicItemID(rawValue: id)
        var request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: itemID)
        let response = try await request.response()
        guard let playlist = response.items.first else {
            throw CatalogPlaybackError.itemNotFound
        }
        return playlist
    }

    private func catalogArtist(id: String) async throws -> Artist {
        let itemID = MusicItemID(rawValue: id)
        var request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: itemID)
        let response = try await request.response()
        guard let artist = response.items.first else {
            throw CatalogPlaybackError.itemNotFound
        }
        return artist
    }

    private enum CatalogPlaybackError: LocalizedError {
        case itemNotFound

        var errorDescription: String? {
            switch self {
            case .itemNotFound: return "Item not found in Apple Music."
            }
        }
    }

    private func mapResults(_ response: MusicCatalogSearchResponse) -> [MediaSearchResult] {
        var results: [MediaSearchResult] = []

        for song in response.songs {
            results.append(
                MediaSearchResult(
                    id: song.id.rawValue,
                    title: song.title,
                    subtitle: song.artistName,
                    kind: .song,
                    artworkURL: song.artwork?.url(width: 120, height: 120)?.absoluteString
                )
            )
        }

        for album in response.albums {
            results.append(
                MediaSearchResult(
                    id: album.id.rawValue,
                    title: album.title,
                    subtitle: album.artistName,
                    kind: .album,
                    artworkURL: album.artwork?.url(width: 120, height: 120)?.absoluteString
                )
            )
        }

        for artist in response.artists {
            results.append(
                MediaSearchResult(
                    id: artist.id.rawValue,
                    title: artist.name,
                    subtitle: "Artist",
                    kind: .artist,
                    artworkURL: artist.artwork?.url(width: 120, height: 120)?.absoluteString
                )
            )
        }

        for playlist in response.playlists {
            results.append(
                MediaSearchResult(
                    id: playlist.id.rawValue,
                    title: playlist.name,
                    subtitle: playlist.curatorName ?? "Playlist",
                    kind: .playlist,
                    artworkURL: playlist.artwork?.url(width: 120, height: 120)?.absoluteString
                )
            )
        }

        return results
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
