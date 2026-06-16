import Foundation

enum MailInboxLoadingPhase: Equatable, Hashable {
    case idle
    case connecting
    case signingIn
    case redirecting
    case loadingInbox
    case renderingMailbox
    case syncingUnread
    case failed(String)

    static let orderedSteps: [MailInboxLoadingPhase] = [
        .connecting,
        .signingIn,
        .redirecting,
        .loadingInbox,
        .renderingMailbox,
        .syncingUnread,
    ]

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .connecting:
            return "Connecting to Gmail"
        case .signingIn:
            return "Checking Google sign-in"
        case .redirecting:
            return "Opening your mailbox"
        case .loadingInbox:
            return "Loading inbox"
        case .renderingMailbox:
            return "Rendering mailbox"
        case .syncingUnread:
            return "Syncing unread counts"
        case .failed(let message):
            return "Could not load inbox"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return ""
        case .connecting:
            return "Starting a secure web session for this account."
        case .signingIn:
            return "Confirm Google sign-in if prompted, or wait while Nucleus restores your session."
        case .redirecting:
            return "Following Google redirects to your inbox."
        case .loadingInbox:
            return "Downloading mail.google.com in the embedded inbox view."
        case .renderingMailbox:
            return "Waiting for Gmail to finish drawing the message list."
        case .syncingUnread:
            return "Fetching unread badges and recent messages for notifications."
        case .failed(let message):
            return message
        }
    }

    var stepNumber: Int? {
        guard let index = MailInboxLoadingPhase.orderedSteps.firstIndex(of: self) else { return nil }
        return index + 1
    }

    static var stepCount: Int { orderedSteps.count }

    func isCompleted(relativeTo current: MailInboxLoadingPhase) -> Bool {
        guard let currentIndex = MailInboxLoadingPhase.orderedSteps.firstIndex(of: current),
              let stepIndex = MailInboxLoadingPhase.orderedSteps.firstIndex(of: self) else {
            return false
        }
        return stepIndex < currentIndex
    }

    func isCurrent(_ current: MailInboxLoadingPhase) -> Bool {
        self == current
    }

    static func phase(for url: URL?) -> MailInboxLoadingPhase {
        guard let path = url?.absoluteString.lowercased() else { return .connecting }
        if path.contains("accounts.google.com") {
            return path.contains("signin") ? .signingIn : .redirecting
        }
        if path.contains("mail.google.com/mail") {
            return .loadingInbox
        }
        if path.contains("google.com") {
            return .redirecting
        }
        return .connecting
    }
}
