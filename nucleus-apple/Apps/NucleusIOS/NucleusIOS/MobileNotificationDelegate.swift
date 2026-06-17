import NucleusCore
import SwiftUI
import UIKit
import UserNotifications

final class MobileNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MobileNotificationDelegate()
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == MeetingReminderScheduler.joinMeetingActionID
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }

        guard let link = response.notification.request.content.userInfo["meetingLink"] as? String,
              let url = URL(string: link) else {
            return
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
}
