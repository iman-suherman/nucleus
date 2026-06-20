import NucleusKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaWorkspaceView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var controller = MediaController.shared
    @State private var showingAddPlaylist = false
    @State private var showingAddShortcut = false
    @State private var newPlaylistName = ""
    @State private var newShortcutName = ""
    @State private var newShortcutDetail = ""
    @State private var showingFileImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                mainColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                quickLaunchColumn
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            controller.refreshNowPlaying()
        }
        .alert("Add Playlist", isPresented: $showingAddPlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Add") {
                appSettings.addMediaFavoritePlaylist(name: newPlaylistName)
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
        }
        .alert("Add Shortcut", isPresented: $showingAddShortcut) {
            TextField("Shortcut name", text: $newShortcutName)
            TextField("Description", text: $newShortcutDetail)
            Button("Add") {
                appSettings.addMediaShortcut(
                    MediaShortcut(name: newShortcutName, detail: newShortcutDetail)
                )
                newShortcutName = ""
                newShortcutDetail = ""
            }
            Button("Cancel", role: .cancel) {
                newShortcutName = ""
                newShortcutDetail = ""
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff],
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Music", systemImage: "music.note")
                .font(.title2.bold())
            Picker("Source", selection: $controller.playbackSource) {
                ForEach(MediaPlaybackSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            Spacer()
            if controller.playbackSource == .localPlayer {
                AirPlayRoutePickerButton()
            }
            if let statusMessage = controller.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchField
            searchStatusSection
            nowPlayingCard
            if !controller.searchResults.isEmpty {
                searchResultsSection
            } else if controller.catalogService.isSearching {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if !controller.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "music.note.list",
                    description: Text(controller.catalogService.lastError ?? "Try a different search term.")
                )
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    @ViewBuilder
    private var searchStatusSection: some View {
        if controller.catalogService.authorizationStatus == .denied {
            HStack {
                Text("Allow Apple Music in System Settings → Privacy & Security → Media & Apple Music.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if controller.catalogService.authorizationStatus != .authorized,
                  !controller.searchQuery.isEmpty {
            HStack {
                Text("Allow Apple Music to search the catalog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Allow Access") {
                    Task { await controller.requestAppleMusicAccess() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        if let scope = controller.catalogService.searchScope, !controller.searchResults.isEmpty {
            Text(scope == .appleMusicCatalog ? "Apple Music catalog" : "Your Music library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }

        if let error = controller.catalogService.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if controller.searchQuery.isEmpty {
            Text("Search Apple Music and your library. Library matches also work via the Music app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Apple Music and your library…", text: $controller.searchQuery)
                .textFieldStyle(.plain)
                .onSubmit { controller.scheduleSearch() }
                .onChange(of: controller.searchQuery) { _, _ in
                    controller.scheduleSearch()
                }
            if !controller.searchQuery.isEmpty {
                Button {
                    controller.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var nowPlayingCard: some View {
        let info = controller.nowPlaying
        return VStack(alignment: .leading, spacing: 14) {
            Text("Now Playing")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                artwork(for: info)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(info.title.isEmpty ? "Nothing playing" : info.title)
                        .font(.title3.bold())
                    Text(info.artist.isEmpty ? "—" : info.artist)
                        .foregroundStyle(.secondary)
                    if !info.album.isEmpty {
                        Text(info.album)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if !info.outputDevice.isEmpty {
                        Label(info.outputDevice, systemImage: "hifispeaker.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if info.duration > 0 {
                MediaProgressBar(
                    progress: info.progress,
                    elapsed: info.elapsed,
                    duration: info.duration,
                    isInteractive: controller.playbackSource == .localPlayer
                ) { progress in
                    controller.seek(to: progress)
                }
            }

            playbackControls
            volumeControl
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func artwork(for info: MediaNowPlayingInfo) -> some View {
        if let urlString = info.artworkURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 18) {
            Button {
                controller.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(controller.shuffleEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(controller.playbackSource != .musicApp)

            Button { controller.previousTrack() } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.plain)

            Button { controller.togglePlayPause() } label: {
                Image(systemName: controller.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Button { controller.nextTrack() } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.plain)

            Button {
                controller.cycleRepeatMode()
            } label: {
                Image(systemName: repeatIconName)
                    .foregroundStyle(controller.repeatMode == .off ? .secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(controller.playbackSource != .musicApp)
        }
        .font(.title3)
    }

    private var repeatIconName: String {
        switch controller.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { controller.volume },
                set: { controller.setVolume($0) }
            ), in: 0...1)
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Results")
                .font(.headline)
            ForEach(controller.searchResults) { result in
                Button {
                    controller.playSearchResult(result)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: result.kind))
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.body.weight(.medium))
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(result.kind.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
    }

    private var quickLaunchColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick Launch")
                    .font(.headline)
                Spacer()
            }

            if !controller.isMusicAppAvailable {
                ContentUnavailableView(
                    "Music App Not Found",
                    systemImage: "music.note.slash",
                    description: Text("Install Apple Music to control playback from Nucleus.")
                )
            }

            favoritePlaylistsSection
            shortcutsSection
            localPlayerSection

            Spacer(minLength: 0)
        }
        .padding()
    }

    private var favoritePlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Playlists")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showingAddPlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }

            if appSettings.mediaFavoritePlaylists.isEmpty {
                Text("Add favorite playlists from your Music library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appSettings.mediaFavoritePlaylists) { playlist in
                    HStack {
                        Button {
                            controller.playPlaylist(named: playlist.name)
                        } label: {
                            Label(playlist.name, systemImage: "music.note.list")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button {
                            appSettings.removeMediaFavoritePlaylist(id: playlist.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shortcuts")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showingAddShortcut = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }

            if appSettings.mediaShortcuts.isEmpty {
                Text("Run Siri Shortcuts for HomePod-specific automations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appSettings.mediaShortcuts) { shortcut in
                    HStack(alignment: .top) {
                        Button {
                            Task { await controller.runShortcut(named: shortcut.name) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(shortcut.name, systemImage: "bolt.fill")
                                if !shortcut.detail.isEmpty {
                                    Text(shortcut.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button {
                            appSettings.removeMediaShortcut(id: shortcut.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var localPlayerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Audio")
                .font(.subheadline.weight(.semibold))
            Text("Play files from Nucleus and route them to AirPlay speakers or HomePods.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                showingFileImporter = true
            } label: {
                Label("Open Audio Files…", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
    }

    private func icon(for kind: MediaSearchKind) -> String {
        switch kind {
        case .song: return "music.note"
        case .album: return "square.stack"
        case .artist: return "person.fill"
        case .playlist: return "music.note.list"
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            controller.reportStatus(error.localizedDescription)
        case .success(let urls):
            let accessible = urls.compactMap { url -> URL? in
                guard url.startAccessingSecurityScopedResource() else { return nil }
                return url
            }
            guard !accessible.isEmpty else {
                controller.reportStatus("Could not access the selected files.")
                return
            }
            controller.loadLocalFiles(urls: accessible)
            accessible.forEach { $0.stopAccessingSecurityScopedResource() }
        }
    }
}

private struct MediaProgressBar: View {
    let progress: Double
    let elapsed: TimeInterval
    let duration: TimeInterval
    let isInteractive: Bool
    let onSeek: (Double) -> Void

    var body: some View {
        VStack(spacing: 4) {
            if isInteractive {
                Slider(value: Binding(
                    get: { progress },
                    set: { onSeek($0) }
                ), in: 0...1)
            } else {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            HStack {
                Text(format(elapsed))
                Spacer()
                Text(format(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct MediaMiniPlayer: View {
    @ObservedObject private var controller = MediaController.shared

    var body: some View {
        if controller.nowPlaying.hasContent {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(controller.nowPlaying.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(controller.nowPlaying.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 180, alignment: .leading)

                Button {
                    controller.togglePlayPause()
                } label: {
                    Image(systemName: controller.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)

                Button {
                    controller.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.borderless)

                Button {
                    AppViewModel.current?.sidebarSelection = .workspace(.media)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open Music workspace")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.4), in: Capsule())
        }
    }
}
