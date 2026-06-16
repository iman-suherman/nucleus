import Foundation

public struct ClipboardPasswordSuggestionPayload: Codable, Equatable, Sendable {
    public var entryID: UUID
    public var password: String
    public var sourceApplication: String
    public var capturedAt: Date
    public var reason: String

    public init(
        entryID: UUID,
        password: String,
        sourceApplication: String,
        capturedAt: Date,
        reason: String
    ) {
        self.entryID = entryID
        self.password = password
        self.sourceApplication = sourceApplication
        self.capturedAt = capturedAt
        self.reason = reason
    }
}

/// Cross-process bridge between Nucleus and the menu bar companion.
public enum NucleusMenuBarBridge {
    public static let darwinRefreshNotification = "net.suherman.nucleus.data.refresh"
    public static let darwinPasswordSuggestionNotification = "net.suherman.nucleus.password.suggestion"

    private static let dismissedKey = "nucleus.menubar.dismissedPasswordHashes"
    private static let suggestionKey = "nucleus.menubar.pendingPasswordSuggestion"

    public static func bridgeDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Nucleus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var bridgeFile: URL {
        bridgeDirectory().appendingPathComponent("menubar-bridge.json")
    }

    private struct BridgeState: Codable {
        var dismissedPasswordHashes: [String]
        var pendingSuggestion: ClipboardPasswordSuggestionPayload?
    }

    private static func loadState() -> BridgeState {
        guard let data = try? Data(contentsOf: bridgeFile),
              let state = try? JSONDecoder().decode(BridgeState.self, from: data) else {
            return BridgeState(dismissedPasswordHashes: [], pendingSuggestion: nil)
        }
        return state
    }

    private static func saveState(_ state: BridgeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: bridgeFile, options: .atomic)
    }

    public static func isDismissedPassword(_ password: String) -> Bool {
        let hash = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return loadState().dismissedPasswordHashes.contains(hash)
    }

    public static func rememberDismissedPassword(_ password: String) {
        var state = loadState()
        let hash = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty, !state.dismissedPasswordHashes.contains(hash) else { return }
        state.dismissedPasswordHashes.append(hash)
        if state.dismissedPasswordHashes.count > 200 {
            state.dismissedPasswordHashes = Array(state.dismissedPasswordHashes.suffix(200))
        }
        saveState(state)
    }

    public static func setPendingSuggestion(_ suggestion: ClipboardPasswordSuggestionPayload?) {
        var state = loadState()
        state.pendingSuggestion = suggestion
        saveState(state)
        if suggestion != nil {
            postDarwinNotification(darwinPasswordSuggestionNotification)
        }
    }

    public static func pendingSuggestion() -> ClipboardPasswordSuggestionPayload? {
        loadState().pendingSuggestion
    }

    public static func clearPendingSuggestion() {
        setPendingSuggestion(nil)
    }

    public static func postDataRefresh() {
        postDarwinNotification(darwinRefreshNotification)
    }

    public static func isNucleusFamilyApp(_ source: String) -> Bool {
        source.localizedCaseInsensitiveContains("Nucleus")
    }

    private static func postDarwinNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    }
}
