import AccountKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let googleOAuthClientID =
        "303349212787-nu4b5rmmgpaa9ps9nfuts1r15jtco63d.apps.googleusercontent.com"

    private enum Keys {
        static let mailSyncInterval = "nucleus.settings.mailSyncInterval"
        static let calendarSyncInterval = "nucleus.settings.calendarSyncInterval"
        static let selectedMailAccountID = "nucleus.settings.selectedMailAccountID"
    }

    static let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

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
        GoogleOAuthConfiguration(clientID: Self.googleOAuthClientID)
    }
}
