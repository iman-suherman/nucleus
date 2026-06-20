import AppKit
import Foundation
import MusicKit

enum MusicCatalogAccessState: Equatable {
    case granted
    case notDetermined
    case denied
    case restricted

    init(_ status: MusicAuthorization.Status) {
        switch status {
        case .authorized:
            self = .granted
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .notDetermined
        }
    }
}

struct MusicAccessSnapshot: Equatable {
    var catalogAccess: MusicCatalogAccessState
    var musicAutomation: MusicAutomationAccessState

    var musicAppInstalled: Bool {
        switch musicAutomation {
        case .musicAppMissing:
            return false
        default:
            return true
        }
    }

    var isCatalogReady: Bool {
        catalogAccess == .granted
    }

    var isAutomationReady: Bool {
        musicAutomation == .granted
    }

    var isFullyReady: Bool {
        isCatalogReady && isAutomationReady
    }

    var needsSetup: Bool {
        !isFullyReady
    }
}

enum MusicAccessSettingsPane {
    case mediaAndAppleMusic
    case automation

    var settingsURL: URL? {
        let path: String
        switch self {
        case .mediaAndAppleMusic:
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Media"
        case .automation:
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        }
        return URL(string: path)
    }
}

enum MusicAccessSetup {
    static func makeSnapshot(
        catalogStatus: MusicAuthorization.Status,
        automation: MusicAutomationAccessState
    ) -> MusicAccessSnapshot {
        MusicAccessSnapshot(
            catalogAccess: MusicCatalogAccessState(catalogStatus),
            musicAutomation: automation
        )
    }

    static func openSettings(_ pane: MusicAccessSettingsPane) {
        guard let url = pane.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
