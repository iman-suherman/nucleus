import AccountKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let googleClientID = "nucleus.settings.googleClientID"
        static let googleClientSecret = "nucleus.settings.googleClientSecret"
        static let mailSyncInterval = "nucleus.settings.mailSyncInterval"
        static let calendarSyncInterval = "nucleus.settings.calendarSyncInterval"
        static let selectedMailAccountID = "nucleus.settings.selectedMailAccountID"
    }

    static let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    @Published var googleClientID: String {
        didSet { UserDefaults.standard.set(googleClientID, forKey: Keys.googleClientID) }
    }

    @Published var googleClientSecret: String {
        didSet { UserDefaults.standard.set(googleClientSecret, forKey: Keys.googleClientSecret) }
    }

    @Published var mailSyncInterval: TimeInterval {
        didSet { UserDefaults.standard.set(mailSyncInterval, forKey: Keys.mailSyncInterval) }
    }

    @Published var calendarSyncInterval: TimeInterval {
        didSet { UserDefaults.standard.set(calendarSyncInterval, forKey: Keys.calendarSyncInterval) }
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

    private init() {
        googleClientID = UserDefaults.standard.string(forKey: Keys.googleClientID) ?? ""
        googleClientSecret = UserDefaults.standard.string(forKey: Keys.googleClientSecret) ?? ""
        mailSyncInterval = UserDefaults.standard.object(forKey: Keys.mailSyncInterval) as? TimeInterval ?? 60
        calendarSyncInterval = UserDefaults.standard.object(forKey: Keys.calendarSyncInterval) as? TimeInterval ?? 300

        if let raw = UserDefaults.standard.string(forKey: Keys.selectedMailAccountID),
           let id = UUID(uuidString: raw) {
            selectedMailAccountID = id
        } else {
            selectedMailAccountID = nil
        }
    }

    var oauthConfiguration: GoogleOAuthConfiguration {
        GoogleOAuthConfiguration(clientID: googleClientID)
    }
}
