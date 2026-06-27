import AppKit
import NucleusKit
import SwiftUI

private enum ActiveTerminal: Equatable {
    case shell
    case attaching(TmuxSession)
    case destroying(TmuxSession)
    case tmux(TmuxSession)

    var embeddedMode: EmbeddedTerminalMode {
        switch self {
        case .shell:
            return .shell
        case .attaching(let session):
            return .shellRunCommand(
                TmuxSessionService.attachCommandFromEmbeddedTerminal(sessionName: session.name)
            )
        case .destroying(let session):
            return .shellRunCommand(
                TmuxSessionService.destroyCommandFromEmbeddedTerminal(sessionName: session.name)
            )
        case .tmux(let session):
            return .tmuxSession(name: session.name)
        }
    }

    var statusLabel: String {
        switch self {
        case .shell:
            return "shell"
        case .attaching(let session), .tmux(let session):
            return session.displayName
        case .destroying(let session):
            return "destroying \(session.displayName)"
        }
    }

    var tmuxSessionName: String? {
        switch self {
        case .shell:
            return nil
        case .attaching(let session), .destroying(let session), .tmux(let session):
            return session.name
        }
    }

    var skipsDetachOnDisappear: Bool {
        switch self {
        case .destroying:
            return true
        default:
            return false
        }
    }
}

private enum NewTerminalKind: String, CaseIterable, Identifiable {
    case shell
    case tmux

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shell: return "Shell"
        case .tmux: return "tmux session"
        }
    }

    var subtitle: String {
        switch self {
        case .shell: return "Normal terminal — attach to other sessions with the commands below."
        case .tmux: return "New tmux session in Nucleus."
        }
    }
}

struct TerminalWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var browser = TmuxSessionBrowser.shared
    @State private var activeTerminal: ActiveTerminal?
    @State private var terminalErrorMessage: String?
    @State private var isPreparingSession = false
    @State private var isDetaching = false
    @State private var showNewSessionSheet = false
    @State private var newSessionName = ""
    @State private var newTerminalKind: NewTerminalKind = .shell
    @State private var copiedAttachSessionName: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                terminalTopBar
                Divider()

                if let errorMessage = browser.errorMessage ?? terminalErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08))
                }

                ZStack {
                    if activeTerminal == nil {
                        ContentUnavailableView {
                            Label("No active terminal", systemImage: "terminal")
                        } description: {
                            Text("Start a shell or tmux session. Copy an attach command below to join an existing tmux session from the terminal.")
                        } actions: {
                            Button("New Session") {
                                prepareNewSessionSheet()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if activeTerminal != nil {
                        terminalLayer
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let prompt = viewModel.dashboardIncomingMailPrompt {
                DashboardIncomingMailOverlay(
                    prompt: prompt,
                    onOpenInbox: viewModel.openDashboardIncomingMail,
                    onDismiss: viewModel.dismissDashboardIncomingMail
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.dashboardIncomingMailPrompt?.id)
        .sheet(isPresented: $showNewSessionSheet) {
            newSessionSheet
        }
        .onAppear {
            browser.startAutoRefresh()
            viewModel.refreshDashboardIncomingMailAlertIfNeeded()
        }
        .onDisappear {
            if let terminal = activeTerminal,
               let sessionName = terminal.tmuxSessionName,
               !terminal.skipsDetachOnDisappear {
                let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath()
                if let tmuxPath {
                    Task {
                        await TmuxSessionService.detachSession(sessionName: sessionName, tmuxPath: tmuxPath)
                    }
                }
            }
            activeTerminal = nil
        }
    }

    private var terminalTopBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    commandLine(title: "Attach (Terminal.app)", command: TmuxSessionService.attachCommand())
                    commandLine(
                        title: "Attach (in Nucleus)",
                        command: TmuxSessionService.attachCommandFromEmbeddedTerminal(sessionName: "<name>")
                    )
                    commandLine(title: "Detach (Terminal.app)", command: TmuxSessionService.detachCommand())
                    commandLine(title: "Detach (Nucleus)", command: "F12  or  ⌘⇧D  or  Detach button")
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        prepareNewSessionSheet()
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparingSession || activeTerminal != nil)

                    if activeTerminal != nil {
                        Button("Detach") {
                            detachActiveTerminal()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDetaching)
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                    }

                    Button {
                        Task { await browser.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(browser.isRefreshing)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Active tmux sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if browser.sessions.isEmpty {
                    Text("none")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(browser.sessions) { session in
                        sessionAttachRow(session)
                    }
                }
            }

            if let activeTerminal {
                Text("Live in Nucleus: \(activeTerminal.statusLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func sessionAttachRow(_ session: TmuxSession) -> some View {
        let attachCommand = TmuxSessionService.attachCommandFromEmbeddedTerminal(sessionName: session.name)
        let isCopied = copiedAttachSessionName == session.name
        let isLiveHere = activeTerminal?.tmuxSessionName == session.name

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.displayName)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.primary)

                Text(sessionSummary(for: session, isLiveHere: isLiveHere))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(attachCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    attachToSession(session)
                } label: {
                    Label("Attach", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(isPreparingSession)

                Button {
                    copyAttachCommand(attachCommand, sessionName: session.name)
                } label: {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    destroySession(session)
                } label: {
                    Label("Destroy", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
                .disabled(isPreparingSession || activeTerminal != nil)
                .help("Attach, send exit, and close this tmux session")
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionSummary(for session: TmuxSession, isLiveHere: Bool) -> String {
        var parts = ["\(session.windowCount)w"]
        if session.isAttached {
            parts.append("attached")
        }
        if isLiveHere {
            parts.append("live here")
        }
        return "(\(parts.joined(separator: ", ")))"
    }

    private func commandLine(title: String, command: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.primary)
        }
    }

    private var newSessionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New terminal session")
                .font(.title3.bold())

            Picker("Session type", selection: $newTerminalKind) {
                ForEach(NewTerminalKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(newTerminalKind.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if newTerminalKind == .tmux {
                TextField("Session name", text: $newSessionName)
                    .textFieldStyle(.roundedBorder)
            }

            if let terminalErrorMessage {
                Text(terminalErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    showNewSessionSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Start Session") {
                    startNewSession()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isPreparingSession)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    @ViewBuilder
    private var terminalLayer: some View {
        let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath() ?? "/opt/homebrew/bin/tmux"

        VStack(spacing: 0) {
            TmuxAttachTerminalView(
                activeMode: activeTerminal?.embeddedMode,
                tmuxPath: tmuxPath,
                onDetachHotkey: {
                    detachActiveTerminal()
                },
                onExit: { exitCode in
                    if isDetaching {
                        self.activeTerminal = nil
                        self.terminalErrorMessage = nil
                        return
                    }
                    if case .tmux = activeTerminal {
                        let code = TmuxSessionService.normalizedExitCode(exitCode) ?? -1
                        if code != 0 {
                            self.terminalErrorMessage =
                                "tmux session failed (exit \(code)). Try a different session name."
                        }
                    } else if case .attaching = activeTerminal {
                        let code = TmuxSessionService.normalizedExitCode(exitCode) ?? -1
                        if code != 0 {
                            self.terminalErrorMessage =
                                "tmux attach failed (exit \(code)). Check that the session is still running."
                        }
                    } else if case .destroying = activeTerminal {
                        self.terminalErrorMessage = nil
                    }
                    self.activeTerminal = nil
                    Task { await browser.refresh() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: activeTerminal == nil ? 0 : .infinity)
            .clipped()
            .opacity(activeTerminal == nil ? 0 : 1)
            .allowsHitTesting(activeTerminal != nil)
            .accessibilityHidden(activeTerminal == nil)
        }
        .allowsHitTesting(activeTerminal != nil)
    }

    private func detachActiveTerminal() {
        guard let terminal = activeTerminal, !isDetaching else { return }

        Task {
            isDetaching = true
            defer { isDetaching = false }

            switch terminal {
            case .shell, .attaching, .destroying:
                terminalErrorMessage = nil
                self.activeTerminal = nil
            case .tmux(let session):
                guard let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath() else {
                    terminalErrorMessage = "tmux path is unavailable."
                    self.activeTerminal = nil
                    return
                }

                await TmuxSessionService.detachSession(sessionName: session.name, tmuxPath: tmuxPath)
                terminalErrorMessage = nil
                self.activeTerminal = nil
                await browser.refresh()
            }
        }
    }

    private func prepareNewSessionSheet() {
        terminalErrorMessage = nil
        newTerminalKind = .shell
        newSessionName = TmuxSessionService.suggestNewSessionName(
            existingSessionNames: browser.sessions.map(\.name)
        )
        showNewSessionSheet = true
    }

    private func startNewSession() {
        terminalErrorMessage = nil

        switch newTerminalKind {
        case .shell:
            showNewSessionSheet = false
            activeTerminal = .shell
        case .tmux:
            startNewTmuxSession(named: newSessionName)
        }
    }

    private func startNewTmuxSession(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let validationError = TmuxSessionService.validateSessionName(name) {
            terminalErrorMessage = validationError
            return
        }

        isPreparingSession = true
        Task {
            defer { isPreparingSession = false }
            guard let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath() else {
                terminalErrorMessage = "tmux path is unavailable."
                return
            }
            if await TmuxSessionService.validateSessionExists(sessionName: name, tmuxPath: tmuxPath) == nil {
                terminalErrorMessage = "Session \"\(name)\" already exists. Pick another name."
                return
            }

            showNewSessionSheet = false
            activeTerminal = .tmux(
                TmuxSession(
                    name: name,
                    windowCount: 1,
                    isAttached: false,
                    lastActivity: Date(),
                    preview: ""
                )
            )
        }
    }

    private func attachToSession(_ session: TmuxSession) {
        terminalErrorMessage = nil
        activeTerminal = .attaching(session)
    }

    private func destroySession(_ session: TmuxSession) {
        terminalErrorMessage = nil
        activeTerminal = .destroying(session)
    }

    private func copyAttachCommand(_ command: String, sessionName: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedAttachSessionName = sessionName
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedAttachSessionName == sessionName {
                copiedAttachSessionName = nil
            }
        }
    }
}
