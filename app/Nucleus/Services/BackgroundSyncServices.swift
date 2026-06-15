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
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Task { await viewModel.syncMail() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class CalendarSyncService {
    private var timer: Timer?
    private weak var viewModel: AppViewModel?

    func start(viewModel: AppViewModel, interval: TimeInterval) {
        self.viewModel = viewModel
        stop()
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.viewModel?.syncCalendarAutomatically()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Task { await viewModel.syncCalendarAutomatically() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
