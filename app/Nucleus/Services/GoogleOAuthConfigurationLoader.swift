import AccountKit
import Foundation

enum GoogleOAuthConfigurationLoader {
    static func loadIntoSessionStore(tokenSynchronizable: Bool = true) async {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? ""
        let clientSecret = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String
        let configuration = GoogleOAuthConfiguration(clientID: clientID)
        await AccountSessionStore.shared.updateConfiguration(
            configuration,
            clientSecret: clientSecret,
            tokenSynchronizable: tokenSynchronizable
        )
    }

    static var isConfigured: Bool {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? ""
        return !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
