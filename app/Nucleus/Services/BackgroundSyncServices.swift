import Foundation
import SwiftData

@MainActor
final class MailSyncService {
    private var timer: Timer?
    private weak var viewModel: AppViewModel?

    func start(viewModel: AppViewModel, interval: TimeInterval) {
        self.viewModel = viewModel
        stop()
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.viewModel?.syncMail()
                self?.pollWebSessionUnreadCounts()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Task {
            await viewModel.syncMail()
            pollWebSessionUnreadCounts()
        }
    }

    private func pollWebSessionUnreadCounts() {
        guard let viewModel else { return }
        for account in viewModel.webSessionAccounts {
            GmailWebView.ensureUnreadSync(accountID: account.id, email: account.email)
        }
        NotificationCenter.default.post(name: .gmailWebUnreadPollNow, object: nil)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
