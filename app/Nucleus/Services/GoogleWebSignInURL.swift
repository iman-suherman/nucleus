import Foundation

enum GoogleWebSignInURL {
    enum Service: String {
        case mail
        case chat
        case calendar = "cl"
    }

    static func signInURL(email: String, continue continueURL: URL, service: Service) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/v3/signin/identifier")
        components?.queryItems = [
            URLQueryItem(name: "service", value: service.rawValue),
            URLQueryItem(name: "continue", value: continueURL.absoluteString),
            URLQueryItem(name: "Email", value: email),
            URLQueryItem(name: "login_hint", value: email),
            URLQueryItem(name: "identifier", value: email),
            URLQueryItem(name: "flowName", value: "GlifWebSignIn"),
            URLQueryItem(name: "flowEntry", value: "ServiceLogin"),
        ]
        return components?.url
    }

    static func prefillEmailScript(email: String) -> String {
        let escaped = jsStringLiteral(email)
        return """
        (function() {
          const email = "\(escaped)";
          const selectors = [
            'input[type="email"]',
            '#identifierId',
            'input[name="identifier"]'
          ];
          for (const selector of selectors) {
            const input = document.querySelector(selector);
            if (input && !input.value) {
              input.value = email;
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              return true;
            }
          }
          return false;
        })();
        """
    }

    static func isGoogleSignInPage(_ urlString: String) -> Bool {
        urlString.contains("accounts.google.com")
            && (urlString.contains("signin/identifier")
                || urlString.contains("signin/accountchooser")
                || urlString.contains("/ServiceLogin"))
    }

    private static func jsStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
