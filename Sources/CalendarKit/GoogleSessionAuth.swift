import CryptoKit
import Foundation

enum GoogleSessionAuth {
    private static let calendarOrigin = "https://calendar.google.com"

    static func sapisidHash(cookies: [HTTPCookie], origin: String = calendarOrigin) -> String? {
        guard let sapisid = sapisidCookieValue(from: cookies) else { return nil }
        let timestamp = Int(Date().timeIntervalSince1970)
        let input = "\(timestamp) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(timestamp)_\(hash)"
    }

    static func sapisidCookieValue(from cookies: [HTTPCookie]) -> String? {
        for name in ["SAPISID", "__Secure-1PAPISID", "__Secure-3PAPISID"] {
            if let value = cookies.first(where: { $0.name == name })?.value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func cookieHeader(from cookies: [HTTPCookie]) -> String {
        var seen = Set<String>()
        return cookies
            .filter { cookie in
                cookie.domain.contains("google.com") && !cookie.value.isEmpty
            }
            .compactMap { cookie -> String? in
                guard seen.insert(cookie.name).inserted else { return nil }
                return "\(cookie.name)=\(cookie.value)"
            }
            .joined(separator: "; ")
    }
}
