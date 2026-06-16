import Combine
import Foundation

/// Lightweight cross-device settings via iCloud Key-Value Store (max 1 MB / 1024 keys).
/// Use for mobile layout and selected account tabs — not note bodies or large payloads.
@MainActor
public final class MobilePreferencesStore: ObservableObject {
    public static let shared = MobilePreferencesStore()

    private static let storageKey = "net.suherman.nucleus.mobilePreferences"
    private let store = NSUbiquitousKeyValueStore.default
    private var externalChangeObserver: AnyCancellable?

    @Published public private(set) var preferences: MobilePreferences

    private init() {
        preferences = Self.load(from: NSUbiquitousKeyValueStore.default) ?? MobilePreferences()
        externalChangeObserver = NotificationCenter.default.publisher(
            for: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.applyExternalChange()
        }
        store.synchronize()
    }

    public func update(_ transform: (inout MobilePreferences) -> Void) {
        var next = preferences
        transform(&next)
        next.updatedAt = Date()
        preferences = next
        persist(next)
    }

    public func replace(with preferences: MobilePreferences) {
        self.preferences = preferences
        persist(preferences)
    }

    private func persist(_ preferences: MobilePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        store.set(data, forKey: Self.storageKey)
        store.synchronize()
    }

    private func applyExternalChange() {
        guard let remote = Self.load(from: store) else { return }
        guard remote.updatedAt >= preferences.updatedAt else { return }
        preferences = remote
    }

    private static func load(from store: NSUbiquitousKeyValueStore) -> MobilePreferences? {
        guard let data = store.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MobilePreferences.self, from: data)
    }
}
