import DatabaseKit
import Foundation
import NucleusKit

@MainActor
final class DashboardAnalysisService {
    static let shared = DashboardAnalysisService()

    static let analysisInterval: TimeInterval = 30 * 60

    private var timer: Timer?
    private weak var viewModel: AppViewModel?
    private let interval = DashboardAnalysisService.analysisInterval

    private init() {}

    func start(viewModel: AppViewModel) {
        stop()
        self.viewModel = viewModel
        runAnalysisIfNeeded(force: true)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runAnalysisIfNeeded(force: false)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
}
