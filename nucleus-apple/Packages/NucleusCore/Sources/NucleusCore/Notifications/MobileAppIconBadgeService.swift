#if os(iOS)
import Foundation
import UserNotifications

/// Keeps the home-screen app icon badge in sync with bill due counts.
@MainActor
public final class MobileAppIconBadgeService {
    public static let shared = MobileAppIconBadgeService()

    private init() {}

    public func syncBillDueCount(_ count: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let badgeCount = max(0, count)
        do {
            try await center.setBadgeCount(badgeCount)
        } catch {
            // Badge updates require notification permission; ignore transient failures.
        }
    }

    public func clear() async {
        await syncBillDueCount(0)
    }
}
#endif
