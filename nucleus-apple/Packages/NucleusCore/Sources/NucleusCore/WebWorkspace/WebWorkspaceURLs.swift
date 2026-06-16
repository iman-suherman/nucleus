import Foundation

public enum WebWorkspaceURLs {
    public static func mailInbox(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://mail.google.com/mail/u/?authuser=\(encoded)")
    }

    public static func mailSignIn(for email: String) -> URL? {
        guard let continueTarget = mailInbox(for: email) else { return nil }
        return GoogleWebSignInURL.signInURL(email: email, continue: continueTarget, service: .mail)
    }

    public static func chat(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://mail.google.com/chat/u/0/?authuser=\(encoded)")
    }

    public static func chatSignIn(for email: String) -> URL? {
        guard let continueTarget = chat(for: email) else { return nil }
        return GoogleWebSignInURL.signInURL(email: email, continue: continueTarget, service: .chat)
    }

    public static func calendarWeek(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://calendar.google.com/calendar/u/0/r/week?authuser=\(encoded)")
    }

    public static func calendarSignIn(for email: String) -> URL? {
        guard let continueTarget = calendarWeek(for: email) else { return nil }
        return GoogleWebSignInURL.signInURL(email: email, continue: continueTarget, service: .calendar)
    }

    public static func initialURL(for surface: WebSurface, email: String, preferSignIn: Bool = false) -> URL? {
        switch surface {
        case .mail:
            return preferSignIn ? mailSignIn(for: email) : mailInbox(for: email)
        case .chat:
            return preferSignIn ? chatSignIn(for: email) : chat(for: email)
        case .calendar:
            return preferSignIn ? calendarSignIn(for: email) : calendarWeek(for: email)
        }
    }

    public static func isLoadedContent(_ url: URL?, for surface: WebSurface) -> Bool {
        guard let path = url?.absoluteString, !path.isEmpty, path != "about:blank" else { return false }
        switch surface {
        case .mail:
            return path.contains("mail.google.com/mail")
        case .chat:
            return path.contains("mail.google.com/chat") || path.contains("chat.google.com")
        case .calendar:
            return path.contains("calendar.google.com/calendar")
        }
    }
}
