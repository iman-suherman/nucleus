import AppKit
import SwiftTerm
import SwiftUI

struct TmuxAttachTerminalView: NSViewRepresentable {
    let sessionName: String
    let tmuxPath: String
    var onExit: (Int32?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionName: sessionName, tmuxPath: tmuxPath, onExit: onExit)
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let view = TerminalHostView(frame: CGRect(x: 0, y: 0, width: 800, height: 520))
        view.coordinator = context.coordinator
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        context.coordinator.scheduleStartIfNeeded()
    }

    static func dismantleNSView(_ nsView: TerminalHostView, coordinator: Coordinator) {
        coordinator.terminate()
    }

    final class Coordinator: NSObject {
        let sessionName: String
        let tmuxPath: String
        let onExit: (Int32?) -> Void

        weak var hostView: TerminalHostView?
        private var terminalView: LocalProcessTerminalView?
        private var hasStarted = false
        private var didReportExit = false

        init(sessionName: String, tmuxPath: String, onExit: @escaping (Int32?) -> Void) {
            self.sessionName = sessionName
            self.tmuxPath = tmuxPath
            self.onExit = onExit
        }

        func scheduleStartIfNeeded() {
            guard let hostView else { return }
            guard !hasStarted else {
                resizeTerminalIfNeeded(in: hostView)
                return
            }
            guard hostView.bounds.width > 20, hostView.bounds.height > 20 else { return }

            hasStarted = true

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

            terminal.startProcess(
                executable: tmuxPath,
                args: TmuxSessionService.attachArguments(sessionName: sessionName),
                environment: TmuxSessionService.enrichedEnvironmentArray(),
                execName: nil
            )
        }

        func terminate() {
            terminalView?.terminate()
            terminalView?.removeFromSuperview()
            terminalView = nil
            hasStarted = false
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
            DispatchQueue.main.async {
                self.onExit(exitCode)
            }
        }
    }
}

extension TmuxAttachTerminalView.Coordinator: LocalProcessTerminalViewDelegate {
    func processTerminated(source: TerminalView, exitCode: Int32?) {
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
