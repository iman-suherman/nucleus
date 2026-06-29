import Foundation

/// Background Gmail web-session unread sync — at most once per minute when Inbox is not active.
@MainActor
final class GmailWebSyncScheduler {
    static let shared = GmailWebSyncScheduler()

    static let interval: TimeInterval = 60

    private var timer: Timer?
    private weak var viewModel: AppViewModel?

    private init() {}

    func start(viewModel: AppViewModel) {
        stop()
        self.viewModel = viewModel
        syncAllAccounts(force: true)
        timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncAllAccounts(force: false)
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func syncAllAccounts(force: Bool = false) {
        guard let viewModel else { return }
        if !force, viewModel.isInboxWorkspaceActive { return }

        let accounts = viewModel.webSessionAccounts
        guard !accounts.isEmpty else { return }

        for account in accounts {
            GmailWebView.ensureUnreadSync(accountID: account.id, email: account.email)
        }
    }

    func syncAccount(accountID: UUID, email: String) {
        GmailWebView.ensureUnreadSync(accountID: accountID, email: email)
        NotificationCenter.default.post(name: .gmailWebUnreadPollNow, object: nil)
    }
}
