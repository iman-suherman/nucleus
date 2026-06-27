import AppKit
import SwiftTerm
import SwiftUI

enum EmbeddedTerminalMode: Equatable {
    case shell
    case shellRunCommand(String)
    case tmuxSession(name: String)
}

struct TmuxAttachTerminalView: NSViewRepresentable {
    let activeMode: EmbeddedTerminalMode?
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
        context.coordinator.sync(activeMode: activeMode, tmuxPath: tmuxPath)
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
        private var scrollMonitor: Any?
        private var keyMonitor: Any?
        private var activeMode: EmbeddedTerminalMode?
        private var didReportExit = false

        init(tmuxPath: String, onDetachHotkey: @escaping () -> Void, onExit: @escaping (Int32?) -> Void) {
            self.tmuxPath = tmuxPath
            self.onDetachHotkey = onDetachHotkey
            self.onExit = onExit
        }

        func sync(activeMode: EmbeddedTerminalMode?, tmuxPath: String) {
            self.tmuxPath = tmuxPath

            if activeMode == self.activeMode {
                scheduleStartIfNeeded()
                return
            }

            if activeMode == nil {
                let terminateProcess: Bool = switch self.activeMode {
                case .shell, .shellRunCommand:
                    true
                case .tmuxSession, nil:
                    false
                }
                clearTerminalView(graceful: !terminateProcess)
                self.activeMode = nil
                return
            }

            if self.activeMode != nil {
                clearTerminalView(graceful: true)
            }

            self.activeMode = activeMode
            didReportExit = false
            scheduleStartIfNeeded()
        }

        func scheduleStartIfNeeded() {
            guard let hostView else { return }
            guard let activeMode else { return }
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
            terminal.changeScrollback(10_000)
            try? terminal.setUseMetal(false)
            terminal.processDelegate = self
            hostView.addSubview(terminal)
            terminalView = terminal
            hostView.window?.makeFirstResponder(terminal)
            startScrollMonitor(for: terminal)

            let launch: (executable: String, args: [String])
            switch activeMode {
            case .shell:
                launch = TmuxSessionService.shellLaunchPlan()
            case .shellRunCommand(let command):
                launch = TmuxSessionService.shellCommandLaunchPlan(command)
            case .tmuxSession(let sessionName):
                launch = TmuxSessionService.newSessionLaunchPlan(sessionName: sessionName, tmuxPath: tmuxPath)
            }

            DispatchQueue.main.async {
                guard self.activeMode == activeMode, self.terminalView === terminal else { return }
                terminal.startProcess(
                    executable: launch.executable,
                    args: launch.args,
                    environment: TmuxSessionService.attachEnvironmentArray(),
                    execName: nil,
                    currentDirectory: TmuxSessionService.defaultHomeDirectory()
                )
            }
        }

        func finalTeardown() {
            stopKeyMonitor()
            stopScrollMonitor()
            clearTerminalView(graceful: false)
            activeMode = nil
        }

        private func clearTerminalView(graceful: Bool) {
            stopKeyMonitor()
            stopScrollMonitor()
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

        private func startScrollMonitor(for terminal: LocalProcessTerminalView) {
            stopScrollMonitor()
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak terminal] event in
                guard let terminal else { return event }
                guard event.window === terminal.window else { return event }
                terminal.scrollWheel(with: event)
                return nil
            }
        }

        private func stopScrollMonitor() {
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
                self.scrollMonitor = nil
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

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        coordinator?.scheduleStartIfNeeded()
    }
}
