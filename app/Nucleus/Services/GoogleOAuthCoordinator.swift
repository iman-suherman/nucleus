import AccountKit
import AuthenticationServices
import AppKit
import Foundation

@MainActor
final class GoogleOAuthCoordinator: NSObject, ObservableObject {
    static let shared = GoogleOAuthCoordinator()

    @Published private(set) var isAuthenticating = false
    @Published var lastError: String?

    private var session: ASWebAuthenticationSession?

    private override init() {
        super.init()
    }

    func signIn(configuration: GoogleOAuthConfiguration, clientSecret: String?) async throws -> (OAuthTokenBundle, GoogleUserProfile) {
        guard let authURL = GoogleOAuthClient.authorizationURL(configuration: configuration) else {
            throw URLError(.badURL)
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let callbackScheme = URL(string: configuration.redirectURI)?.scheme ?? "net.suherman.nucleus"

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard
                    let callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: URLError(.badURL))
                    return
                }
                continuation.resume(returning: code)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        let tokens = try await GoogleOAuthClient.exchangeCode(
            code,
            configuration: configuration,
            clientSecret: clientSecret
        )
        let profile = try await GoogleOAuthClient.fetchProfile(accessToken: tokens.accessToken)
        return (tokens, profile)
    }
}

extension GoogleOAuthCoordinator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
