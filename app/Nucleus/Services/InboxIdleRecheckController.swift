import AppKit
import Foundation

@MainActor
final class InboxIdleRecheckController {
    static let shared = InboxIdleRecheckController()

    private static let idleDuration: UInt64 = 45 * 1_000_000_000

    private weak var viewModel: AppViewModel?
    private var idleTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private(set) var isActive = false

    private init() {}

    func begin(viewModel: AppViewModel) {
        stop()
        self.viewModel = viewModel
        isActive = true
        installEventMonitorIfNeeded()
        scheduleRecheck()
    }

    func pause() {
        idleTask?.cancel()
        idleTask = nil
    }

    func resumeIfActive() {
        guard isActive else { return }
        scheduleRecheck()
    }

    func stop() {
        isActive = false
        pause()
        removeEventMonitor()
        viewModel = nil
    }

    func recordActivity() {
        guard isActive else { return }
        scheduleRecheck()
    }

    private func scheduleRecheck() {
        pause()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleDuration)
            guard !Task.isCancelled, let self, self.isActive else { return }
            await self.viewModel?.completeDashboardMailAlertInboxRecheck()
            self.stop()
        }
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            self?.recordActivity()
            return event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
