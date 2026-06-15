import Foundation
import WebKit

@MainActor
enum CalendarWebAuthIndexStore {
    private static func key(for accountID: UUID) -> String {
        "nucleus.calendar.authUserIndex.\(accountID.uuidString)"
    }

    static func index(for accountID: UUID) -> Int? {
        guard UserDefaults.standard.object(forKey: key(for: accountID)) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key(for: accountID))
    }

    static func setIndex(_ index: Int, for accountID: UUID) {
        UserDefaults.standard.set(index, forKey: key(for: accountID))
    }

    static func index(from url: URL) -> Int? {
        let path = url.absoluteString
        guard let regex = try? NSRegularExpression(pattern: #"/calendar/u/(\d+)/"#),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range(at: 1), in: path),
              let index = Int(path[range]) else {
            return nil
        }
        return index
    }
}

extension GmailWebSessionStore {
    static func googleSessionCookies(for accountID: UUID) async -> [HTTPCookie] {
        await cookies(for: accountID)
    }
}
