import AppKit
import Foundation
import NucleusKit

@MainActor
final class WorkspaceIdleController {
    static let shared = WorkspaceIdleController()

    private static let idleDuration: UInt64 = 5 * 60 * 1_000_000_000

    private weak var viewModel: AppViewModel?
    private var idleTask: Task<Void, Never>?
    private var eventMonitor: Any?

    private init() {}

    func start(viewModel: AppViewModel) {
        stop()
        self.viewModel = viewModel
        installEventMonitor()
        scheduleIdleReturn()
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        viewModel = nil
    }

    func recordActivity() {
        scheduleIdleReturn()
    }

    private func scheduleIdleReturn() {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleDuration)
            guard !Task.isCancelled else { return }
            self?.returnToDashboardIfNeeded()
        }
    }

    private func returnToDashboardIfNeeded() {
        guard let viewModel, !viewModel.isStartingUp else { return }
        guard case .workspace(let pane) = viewModel.sidebarSelection, pane != .dashboard else { return }

        viewModel.sidebarSelection = .workspace(.dashboard)
        AppSettings.shared.selectedWorkspacePane = WorkspacePane.dashboard.rawValue
        scheduleIdleReturn()
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            self?.recordActivity()
            return event
        }
    }
}
