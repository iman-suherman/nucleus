import AppKit
import DatabaseKit
import Foundation
import NucleusKit

@MainActor
final class DashboardAnalysisService {
    static let shared = DashboardAnalysisService()

    static let analysisInterval: TimeInterval = 30 * 60

    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private weak var viewModel: AppViewModel?
    private let interval = DashboardAnalysisService.analysisInterval

    private init() {}

    func start(viewModel: AppViewModel) {
        stop()
        self.viewModel = viewModel
        installActivationObserver()
        runAnalysisIfNeeded(force: false)
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func runAnalysisIfNeeded(force: Bool) {
        guard let viewModel else { return }

        if !force,
           let analyzedAt = viewModel.dashboardAnalyzedAt,
           Date().timeIntervalSince(analyzedAt) < interval {
            return
        }

        viewModel.persistDashboardAnalysis()
    }

    func forceAnalysis() {
        runAnalysisIfNeeded(force: true)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runAnalysisIfNeeded(force: false)
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func installActivationObserver() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.runAnalysisIfNeeded(force: false)
            }
        }
    }
}
