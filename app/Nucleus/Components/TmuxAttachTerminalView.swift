import AppKit
import SwiftTerm
import SwiftUI

struct TmuxAttachTerminalView: NSViewRepresentable {
    let activeSessionName: String?
    let tmuxPath: String
    var onDetachHotkey: () -> Void
    var onExit: (Int32?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(tmuxPath: tmuxPath, onDetachHotkey: onDetachHotkey, onExit: onExit)
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let view = TerminalHostView(frame: CGRect(x: 0, y: 0, width: 800, height: 520))
        view.coordinator = context.coordinator
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        context.coordinator.sync(activeSessionName: activeSessionName, tmuxPath: tmuxPath)
    }

    static func dismantleNSView(_ nsView: TerminalHostView, coordinator: Coordinator) {
        coordinator.finalTeardown()
    }

    final class Coordinator: NSObject {
        private(set) var tmuxPath: String
        let onDetachHotkey: () -> Void
        let onExit: (Int32?) -> Void

        weak var hostView: TerminalHostView?
        private var terminalView: LocalProcessTerminalView?
        private var keyMonitor: Any?
        private var activeSessionName: String?
        private var didReportExit = false

        init(tmuxPath: String, onDetachHotkey: @escaping () -> Void, onExit: @escaping (Int32?) -> Void) {
            self.tmuxPath = tmuxPath
            self.onDetachHotkey = onDetachHotkey
            self.onExit = onExit
        }

        func sync(activeSessionName: String?, tmuxPath: String) {
            self.tmuxPath = tmuxPath

            if activeSessionName == self.activeSessionName {
                scheduleStartIfNeeded()
                return
            }

            if activeSessionName == nil {
                clearTerminalView(graceful: true)
                self.activeSessionName = nil
                return
            }

            if self.activeSessionName != nil {
                clearTerminalView(graceful: true)
            }

            self.activeSessionName = activeSessionName
            didReportExit = false
            scheduleStartIfNeeded()
        }

        func scheduleStartIfNeeded() {
            guard let hostView else { return }
            guard let sessionName = activeSessionName else { return }
            guard terminalView == nil else {
                resizeTerminalIfNeeded(in: hostView)
                return
            }
            guard hostView.bounds.width > 20, hostView.bounds.height > 20 else { return }

            startKeyMonitor()

            let terminal = LocalProcessTerminalView(frame: hostView.bounds)
            terminal.autoresizingMask = [.width, .height]
            terminal.wantsLayer = true
            terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            terminal.configureNativeColors()
            terminal.nativeBackgroundColor = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)
            terminal.nativeForegroundColor = NSColor(calibratedRed: 0.86, green: 0.92, blue: 0.86, alpha: 1)
            terminal.layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
            try? terminal.setUseMetal(false)
            terminal.processDelegate = self
            hostView.addSubview(terminal)
            terminalView = terminal

            let launch = TmuxSessionService.newSessionLaunchPlan(sessionName: sessionName, tmuxPath: tmuxPath)
            DispatchQueue.main.async {
                guard self.activeSessionName == sessionName, self.terminalView === terminal else { return }
                terminal.startProcess(
                    executable: launch.executable,
                    args: launch.args,
                    environment: TmuxSessionService.attachEnvironmentArray(),
                    execName: nil
                )
            }
        }

        func finalTeardown() {
            stopKeyMonitor()
            clearTerminalView(graceful: false)
            activeSessionName = nil
        }

        private func clearTerminalView(graceful: Bool) {
            stopKeyMonitor()
            guard let terminalView else { return }

            if graceful {
                terminalView.processDelegate = nil
            } else {
                terminalView.terminate()
            }

            terminalView.removeFromSuperview()
            self.terminalView = nil
        }

        private func startKeyMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if Self.matchesDetachHotkey(event) {
                    self.onDetachHotkey()
                    return nil
                }
                return event
            }
        }

        private func stopKeyMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        private static func matchesDetachHotkey(_ event: NSEvent) -> Bool {
            if event.keyCode == 111 {
                return true
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), flags.contains(.shift) else { return false }
            return event.charactersIgnoringModifiers?.lowercased() == "d"
        }

        private func resizeTerminalIfNeeded(in hostView: TerminalHostView) {
            guard let terminalView else { return }
            if terminalView.frame.size != hostView.bounds.size {
                terminalView.frame = hostView.bounds
                terminalView.needsLayout = true
            }
        }

        private func reportExitIfNeeded(_ exitCode: Int32?) {
            guard !didReportExit else { return }
            didReportExit = true
            let normalized = TmuxSessionService.normalizedExitCode(exitCode)
            DispatchQueue.main.async {
                self.onExit(normalized)
            }
        }
    }
}

extension TmuxAttachTerminalView.Coordinator: LocalProcessTerminalViewDelegate {
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        clearTerminalView(graceful: true)
        reportExitIfNeeded(exitCode)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

final class TerminalHostView: NSView {
    weak var coordinator: TmuxAttachTerminalView.Coordinator?

    override func layout() {
        super.layout()
        coordinator?.scheduleStartIfNeeded()
    }
}
