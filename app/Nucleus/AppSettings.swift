import Combine
import Foundation
import SwiftUI
import UserNotifications

enum MailNotificationSound: String, CaseIterable, Identifiable {
    case funky = "Funky"
    case nucleusMail = "NucleusMail"
    case system = "System"
    case silent = "Silent"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .funky: return "Funky"
        case .nucleusMail: return "Nucleus Mail"
        case .system: return "System default"
        case .silent: return "Silent"
        }
    }

    var notificationSound: UNNotificationSound? {
        switch self {
        case .funky:
            return UNNotificationSound(named: UNNotificationSoundName("Funky.caf"))
        case .nucleusMail:
            return UNNotificationSound(named: UNNotificationSoundName("NucleusMail.caf"))
        case .system:
            return .default
        case .silent:
            return nil
        }
    }

    var previewBundleURL: URL? {
        switch self {
        case .silent, .system:
            return nil
        case .funky, .nucleusMail:
            return Bundle.main.url(forResource: rawValue, withExtension: "caf", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: rawValue, withExtension: "caf")
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let mailSyncInterval = "nucleus.settings.mailSyncInterval"
        static let mailNotificationSound = "nucleus.settings.mailNotificationSound"
        static let selectedMailAccountID = "nucleus.settings.selectedMailAccountID"
        static let selectedCalendarAccountID = "nucleus.settings.selectedCalendarAccountID"
        static let selectedChatAccountID = "nucleus.settings.selectedChatAccountID"
    }

    static let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    @Published var mailSyncInterval: TimeInterval {
        didSet { UserDefaults.standard.set(mailSyncInterval, forKey: Keys.mailSyncInterval) }
    }

    @Published var mailNotificationSound: MailNotificationSound {
        didSet { UserDefaults.standard.set(mailNotificationSound.rawValue, forKey: Keys.mailNotificationSound) }
    }

    @Published var selectedMailAccountID: UUID? {
        didSet {
            if let selectedMailAccountID {
                UserDefaults.standard.set(selectedMailAccountID.uuidString, forKey: Keys.selectedMailAccountID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedMailAccountID)
            }
        }
    }

    @Published var selectedCalendarAccountID: UUID? {
        didSet {
            if let selectedCalendarAccountID {
                UserDefaults.standard.set(selectedCalendarAccountID.uuidString, forKey: Keys.selectedCalendarAccountID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedCalendarAccountID)
            }
        }
    }

    @Published var selectedChatAccountID: UUID? {
        didSet {
            if let selectedChatAccountID {
                UserDefaults.standard.set(selectedChatAccountID.uuidString, forKey: Keys.selectedChatAccountID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedChatAccountID)
            }
        }
    }

    private init() {
        mailSyncInterval = UserDefaults.standard.object(forKey: Keys.mailSyncInterval) as? TimeInterval ?? 60
        if let raw = UserDefaults.standard.string(forKey: Keys.mailNotificationSound),
           let sound = MailNotificationSound(rawValue: raw) {
            mailNotificationSound = sound
        } else {
            mailNotificationSound = .nucleusMail
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.selectedMailAccountID),
           let id = UUID(uuidString: raw) {
            selectedMailAccountID = id
        } else {
            selectedMailAccountID = nil
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.selectedCalendarAccountID),
           let id = UUID(uuidString: raw) {
            selectedCalendarAccountID = id
        } else {
            selectedCalendarAccountID = nil
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.selectedChatAccountID),
           let id = UUID(uuidString: raw) {
            selectedChatAccountID = id
        } else {
            selectedChatAccountID = nil
        }
    }
}
