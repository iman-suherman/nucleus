import AppKit
import Foundation
import NucleusKit

enum MusicAppScriptController {
    private enum ScriptFailure: Error {
        case message(String)
    }

    static func play() {
        run("tell application \"Music\" to play")
    }

    static func pause() {
        run("tell application \"Music\" to pause")
    }

    static func playPause() {
        run("""
        tell application "Music"
            if player state is playing then
                pause
            else
                play
            end if
        end tell
        """)
    }

    static func nextTrack() {
        run("tell application \"Music\" to next track")
    }

    static func previousTrack() {
        run("tell application \"Music\" to previous track")
    }

    static func setVolume(_ volume: Int) {
        let clamped = max(0, min(100, volume))
        run("tell application \"Music\" to set sound volume to \(clamped)")
    }

    static func playPlaylist(named name: String) {
        let escaped = escapeAppleScriptString(name)
        run("tell application \"Music\" to play playlist \"\(escaped)\"")
    }

    static func playAlbum(named title: String, artist: String? = nil) {
        let escapedTitle = escapeAppleScriptString(title)
        if let artist, !artist.isEmpty {
            let escapedArtist = escapeAppleScriptString(artist)
            run("""
            tell application "Music"
                set matches to (search library playlist 1 for "\(escapedTitle)" only albums)
                repeat with anAlbum in matches
                    if artist of anAlbum is "\(escapedArtist)" then
                        play anAlbum
                        return
                    end if
                end repeat
                play album "\(escapedTitle)"
            end tell
            """)
        } else {
            run("tell application \"Music\" to play album \"\(escapedTitle)\"")
        }
    }

    static func playTrack(named title: String, artist: String? = nil) {
        let escapedTitle = escapeAppleScriptString(title)
        if let artist, !artist.isEmpty {
            let escapedArtist = escapeAppleScriptString(artist)
            run("""
            tell application "Music"
                set matches to (search library playlist 1 for "\(escapedTitle)" only songs)
                repeat with aTrack in matches
                    if artist of aTrack is "\(escapedArtist)" then
                        play aTrack
                        return
                    end if
                end repeat
                play track "\(escapedTitle)"
            end tell
            """)
        } else {
            run("tell application \"Music\" to play track \"\(escapedTitle)\"")
        }
    }

    static func setShuffleEnabled(_ enabled: Bool) {
        run("tell application \"Music\" to set shuffle enabled to \(enabled)")
    }

    static func setSongRepeat(_ mode: MediaRepeatMode) {
        let value: String
        switch mode {
        case .off: value = "off"
        case .all: value = "all"
        case .one: value = "one"
        }
        run("tell application \"Music\" to set song repeat to \(value)")
    }

    static func fetchNowPlaying() -> MediaNowPlayingInfo? {
        let script = """
        tell application "Music"
            if player state is stopped then
                try
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackDuration to duration of current track
                    set trackPosition to player position
                    return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & (trackDuration as string) & "|||" & (trackPosition as string) & "|||stopped|||"
                on error
                    return ""
                end try
            end if
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            set playerState to player state as string
            set outputName to ""
            try
                set outputName to name of current AirPlay devices
            end try
            return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & (trackDuration as string) & "|||" & (trackPosition as string) & "|||" & playerState & "|||" & outputName
        end tell
        """

        guard let result = runReturningString(script), !result.isEmpty else {
            return nil
        }

        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let duration = TimeInterval(parts[3]) ?? 0
        let elapsed = TimeInterval(parts[4]) ?? 0
        let playerState = parsePlayerState(parts[5])
        let output = parts.count > 6 ? parts[6] : ""

        return MediaNowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            duration: duration,
            elapsed: elapsed,
            isPlaying: playerState == .playing,
            playerState: playerState,
            outputDevice: output
        )
    }

    static func fetchVolume() -> Int? {
        guard let value = runReturningString("tell application \"Music\" to return sound volume") else {
            return nil
        }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func fetchAirPlayDevices() -> MusicAirPlayDevicesResult {
        guard isInstalled() else {
            return MusicAirPlayDevicesResult(
                devices: [],
                errorMessage: "Apple Music is not installed."
            )
        }

        switch probeAutomationAccess() {
        case .denied:
            return MusicAirPlayDevicesResult(
                devices: [],
                errorMessage: "Allow Nucleus to control Music.app in System Settings → Privacy & Security → Automation."
            )
        case .musicAppMissing:
            return MusicAirPlayDevicesResult(
                devices: [],
                errorMessage: "Apple Music is not installed."
            )
        case .failed(let message):
            return MusicAirPlayDevicesResult(devices: [], errorMessage: message)
        case .granted:
            break
        }

        _ = runReturningString("""
        tell application "Music"
            if not running then launch
        end tell
        """)

        let script = """
        tell application "Music"
            set output to ""
            repeat with d in AirPlay devices
                set output to output & (name of d) & "|||" & (selected of d) & "###"
            end repeat
            return output
        end tell
        """

        switch runReturningResult(script) {
        case .failure(.message(let message)):
            return MusicAirPlayDevicesResult(devices: [], errorMessage: message)
        case .success(let raw):
            let devices = parseAirPlayDevices(raw)
            if devices.isEmpty {
                return MusicAirPlayDevicesResult(
                    devices: [],
                    errorMessage: "No AirPlay speakers found. Open Music once and make sure HomePods or AirPlay devices are on the same network."
                )
            }
            return MusicAirPlayDevicesResult(devices: devices, errorMessage: nil)
        }
    }

    private static func parseAirPlayDevices(_ raw: String) -> [(name: String, isSelected: Bool)] {
        guard !raw.isEmpty else { return [] }

        return raw
            .split(separator: "###", omittingEmptySubsequences: true)
            .compactMap { entry -> (name: String, isSelected: Bool)? in
                let parts = entry.split(separator: "|||", omittingEmptySubsequences: false).map(String.init)
                guard let name = parts.first, !name.isEmpty else { return nil }
                let isSelected = parts.count > 1 && parts[1].lowercased() == "true"
                return (name: name, isSelected: isSelected)
            }
    }

    static func setAirPlayDevice(named name: String) {
        let escaped = escapeAppleScriptString(name)
        run("""
        tell application "Music"
            set current AirPlay devices to AirPlay device "\(escaped)"
        end tell
        """)
    }

    static func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") != nil
    }

    /// Harmless probe used to detect (and trigger) Automation permission for Music.app.
    static func probeAutomationAccess() -> MusicAutomationAccessState {
        guard isInstalled() else {
            return .musicAppMissing
        }

        switch runReturningResult("tell application \"Music\" to return name") {
        case .success:
            return .granted
        case .failure(.message(let message)):
            if isAutomationDenied(message) {
                return .denied
            }
            return .failed(message)
        }
    }

    static func requestAutomationAccess() {
        _ = probeAutomationAccess()
    }

    static func searchLibrary(query: String, limit: Int = 12) -> (results: [MediaSearchResult], error: String?) {
        guard isInstalled() else {
            return ([], "Apple Music is not installed.")
        }

        let escaped = escapeAppleScriptString(query)
        let script = """
        tell application "Music"
            set q to "\(escaped)"
            set output to ""
            set counter to 0
            set foundSongs to (search library playlist 1 for q only songs)
            repeat with t in foundSongs
                if counter ≥ \(limit) then exit repeat
                set output to output & (name of t) & "|||" & (artist of t) & "|||song###"
                set counter to counter + 1
            end repeat
            set foundAlbums to (search library playlist 1 for q only albums)
            repeat with a in foundAlbums
                if counter ≥ \(limit) then exit repeat
                set output to output & (name of a) & "|||" & (artist of a) & "|||album###"
                set counter to counter + 1
            end repeat
            set foundArtists to (search library playlist 1 for q only artists)
            repeat with ar in foundArtists
                if counter ≥ \(limit) then exit repeat
                set output to output & (name of ar) & "|||Artist|||artist###"
                set counter to counter + 1
            end repeat
            repeat with p in user playlists
                if counter ≥ \(limit) then exit repeat
                if (name of p as string) contains q ignoring case then
                    set output to output & (name of p) & "|||Playlist|||playlist###"
                    set counter to counter + 1
                end if
            end repeat
            return output
        end tell
        """

        switch runReturningResult(script) {
        case .failure(let error):
            switch error {
            case .message(let message):
                return ([], message)
            }
        case .success(let raw):
            let results = parseLibrarySearchResults(raw, query: query)
            if results.isEmpty {
                return ([], "No matches in your Music library for “\(query)”.")
            }
            return (results, nil)
        }
    }

    private static func parseLibrarySearchResults(_ raw: String, query: String) -> [MediaSearchResult] {
        guard !raw.isEmpty else { return [] }

        return raw
            .split(separator: "###", omittingEmptySubsequences: true)
            .compactMap { entry -> MediaSearchResult? in
                let parts = entry.split(separator: "|||", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3,
                      let kind = MediaSearchKind(rawValue: parts[2]) else {
                    return nil
                }
                let title = parts[0]
                let subtitle = parts[1]
                let id = "library-\(kind.rawValue)-\(title)-\(subtitle)".lowercased()
                return MediaSearchResult(id: id, title: title, subtitle: subtitle, kind: kind)
            }
    }

    private static func run(_ source: String) {
        _ = runReturningResult(source)
    }

    @discardableResult
    private static func runReturningString(_ source: String) -> String? {
        switch runReturningResult(source) {
        case .success(let value):
            return value
        case .failure:
            return nil
        }
    }

    private static func runReturningResult(_ source: String) -> Result<String, ScriptFailure> {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.message("Could not run Music automation."))
        }
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "Music automation was denied or failed."
            return .failure(.message(message))
        }
        return .success(descriptor.stringValue ?? "")
    }

    private static func parsePlayerState(_ raw: String) -> MediaPlayerState {
        switch raw.lowercased() {
        case "playing":
            return .playing
        case "paused", "interrupted":
            return .paused
        default:
            return .stopped
        }
    }

    private static func escapeAppleScriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func isAutomationDenied(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("not authorized to send apple events")
            || normalized.contains("appleevent handler failed")
            || message.contains("-1743")
    }
}

enum MusicAutomationAccessState: Equatable {
    case granted
    case denied
    case musicAppMissing
    case failed(String)
}

struct MusicAirPlayDevicesResult {
    var devices: [(name: String, isSelected: Bool)]
    var errorMessage: String?
}
