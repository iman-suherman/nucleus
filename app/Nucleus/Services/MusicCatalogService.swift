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

    func play(_ result: MediaSearchResult) {
        switch result.kind {
        case .song:
            MusicAppScriptController.playTrack(named: result.title, artist: result.subtitle.nilIfEmpty)
        case .playlist:
            MusicAppScriptController.playPlaylist(named: result.title)
        case .album:
            MusicAppScriptController.playTrack(named: result.title, artist: result.subtitle.nilIfEmpty)
        case .artist:
            MusicAppScriptController.playTrack(named: result.title)
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
