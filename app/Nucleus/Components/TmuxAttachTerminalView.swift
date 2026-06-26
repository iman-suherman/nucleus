import AppKit
import SwiftTerm
import SwiftUI

struct TmuxAttachTerminalView: NSViewRepresentable {
    let sessionName: String
    let tmuxPath: String
    var onDetach: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionName: sessionName, tmuxPath: tmuxPath, onDetach: onDetach)
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
        let onDetach: () -> Void

        weak var hostView: TerminalHostView?
        private var terminalView: LocalProcessTerminalView?
        private var hasStarted = false
        private var didReportDetach = false

        init(sessionName: String, tmuxPath: String, onDetach: @escaping () -> Void) {
            self.sessionName = sessionName
            self.tmuxPath = tmuxPath
            self.onDetach = onDetach
        }

        func scheduleStartIfNeeded() {
            guard let hostView else { return }
            guard !hasStarted else { return }
            guard hostView.bounds.width > 20, hostView.bounds.height > 20 else { return }

            hasStarted = true

            let terminal = LocalProcessTerminalView(frame: hostView.bounds)
            terminal.autoresizingMask = [.width, .height]
            terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            terminal.processDelegate = self
            hostView.addSubview(terminal)
            terminalView = terminal

            var environment = ProcessInfo.processInfo.environment
            environment["TERM"] = environment["TERM"] ?? "xterm-256color"
            let environmentArray = environment.map { "\($0.key)=\($0.value)" }

            terminal.startProcess(
                executable: tmuxPath,
                args: ["attach", "-d", "-t", sessionName],
                environment: environmentArray,
                execName: nil
            )
        }

        func terminate() {
            terminalView?.terminate()
            terminalView?.removeFromSuperview()
            terminalView = nil
        }

        private func reportDetachIfNeeded() {
            guard !didReportDetach else { return }
            didReportDetach = true
            DispatchQueue.main.async {
                self.onDetach()
            }
        }
    }
}

extension TmuxAttachTerminalView.Coordinator: LocalProcessTerminalViewDelegate {
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        reportDetachIfNeeded()
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
