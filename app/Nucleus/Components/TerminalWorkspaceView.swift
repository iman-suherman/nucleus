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
    case tmux
    case shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tmux: return "tmux session"
        case .shell: return "Shell"
        }
    }

    var subtitle: String {
        switch self {
        case .tmux: return "New tmux session in Nucleus. Starts in ~/src when present, otherwise ~, with ls -l."
        case .shell: return "Normal terminal — attach to other sessions with the commands below."
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
    @State private var newTerminalKind: NewTerminalKind = .tmux
    @State private var copiedAttachSessionName: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                terminalToolbar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)

                if let errorMessage = browser.errorMessage ?? terminalErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08))
                }

                if activeTerminal != nil {
                    ScrollView(.vertical, showsIndicators: true) {
                        terminalScrollContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 340)

                    Divider()

                    terminalLayer
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        terminalScrollContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if browser.sessions.isEmpty {
                        Divider()

                        ContentUnavailableView {
                            Label("No active terminal", systemImage: "terminal")
                        } description: {
                            Text("Start a tmux session (default) or shell. Attach commands appear above once tmux sessions are running.")
                        } actions: {
                            Button("New Session") {
                                prepareNewSessionSheet()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxHeight: 220)
                    }
                }
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
            browser.setAutoRefreshSuspended(activeTerminal != nil)
            viewModel.refreshDashboardIncomingMailAlertIfNeeded()
        }
        .onChange(of: activeTerminal != nil) { _, isEmbeddedTerminalActive in
            browser.setAutoRefreshSuspended(isEmbeddedTerminalActive)
        }
        .onDisappear {
            browser.stopAutoRefresh()
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

    private var terminalToolbar: some View {
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

            Spacer()

            Button {
                Task { await browser.refresh(manual: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(browser.isRefreshing)
        }
    }

    private var terminalScrollContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    commandLine(title: "Attach (Terminal.app)", command: TmuxSessionService.attachCommand())
                    commandLine(
                        title: "Attach (In Nucleus)",
                        command: TmuxSessionService.attachCommandFromEmbeddedTerminal(sessionName: "<name>")
                    )
                    commandLine(title: "Detach (Terminal.app)", command: TmuxSessionService.detachCommand())
                    commandLine(title: "Detach (Nucleus)", command: "F12  or  ⌘⇧D  or  Detach button")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let activeTerminal {
                    activeSessionBadge(activeTerminal)
                        .frame(minWidth: 200, maxWidth: 260, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("List of available tmux sessions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Drag cards to reorder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if browser.sessions.isEmpty {
                    Text("none")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ForEach(browser.sessions) { session in
                            sessionCard(session)
                                .draggable(session.name)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let draggedName = items.first else { return false }
                                    browser.moveSession(draggedName, before: session.name)
                                    return true
                                }
                        }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let draggedName = items.first else { return false }
                        browser.moveSessionToEnd(draggedName)
                        return true
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func activeSessionBadge(_ terminal: ActiveTerminal) -> some View {
        let accent = activeSessionAccent(for: terminal)
        let subtitle = activeSessionSubtitle(for: terminal)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text("Running in Nucleus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
            }

            Text(terminal.statusLabel)
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.55), lineWidth: 1.5)
        }
    }

    private func activeSessionAccent(for terminal: ActiveTerminal) -> Color {
        switch terminal {
        case .shell:
            return .blue
        case .attaching:
            return .orange
        case .destroying:
            return .red
        case .tmux:
            return .green
        }
    }

    private func activeSessionSubtitle(for terminal: ActiveTerminal) -> String {
        switch terminal {
        case .shell:
            return "Shell session. Attach to tmux with the commands on the left."
        case .attaching:
            return "Connecting to tmux. Detach with F12, ⌘⇧D, or the Detach button."
        case .destroying:
            return "Closing tmux session."
        case .tmux:
            return "Live tmux session. Detach with F12, ⌘⇧D, or the Detach button."
        }
    }
    private func sessionCard(_ session: TmuxSession) -> some View {
        let attachCommand = TmuxSessionService.attachCommandFromEmbeddedTerminal(sessionName: session.name)
        let isCopied = copiedAttachSessionName == session.name
        let cardState = sessionCardState(for: session)
        let accent = cardState.accent

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent ?? .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(sessionSummary(for: session, cardState: cardState))
                        .font(.caption2)
                        .foregroundStyle(accent ?? .secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .help("Drag to reorder")
            }

            Text(attachCommand)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    attachToSession(session)
                } label: {
                    Label("Attach", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isPreparingSession)

                Button {
                    copyAttachCommand(attachCommand, sessionName: session.name)
                } label: {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    destroySession(session)
                } label: {
                    Label("Destroy", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(isPreparingSession || activeTerminal != nil)
                .help("Attach, send exit, and close this tmux session")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            cardState.background,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    cardState.border,
                    lineWidth: cardState.borderWidth
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private struct SessionCardState {
        let accent: Color?
        let background: Color
        let border: Color
        let borderWidth: CGFloat
        let statusLabel: String?
    }

    private func sessionCardState(for session: TmuxSession) -> SessionCardState {
        if activeTerminal?.tmuxSessionName == session.name {
            return SessionCardState(
                accent: .green,
                background: Color.green.opacity(0.12),
                border: Color.green.opacity(0.55),
                borderWidth: 1.5,
                statusLabel: "live here"
            )
        }

        if session.isAttached {
            return SessionCardState(
                accent: .orange,
                background: Color.orange.opacity(0.10),
                border: Color.orange.opacity(0.45),
                borderWidth: 1.25,
                statusLabel: "attached elsewhere"
            )
        }

        return SessionCardState(
            accent: nil,
            background: Color.primary.opacity(0.04),
            border: Color.primary.opacity(0.08),
            borderWidth: 1,
            statusLabel: nil
        )
    }

    private func sessionSummary(for session: TmuxSession, cardState: SessionCardState) -> String {
        var parts = ["\(session.windowCount)w"]
        if let statusLabel = cardState.statusLabel {
            parts.append(statusLabel)
        } else if session.isAttached {
            parts.append("attached")
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
        newTerminalKind = .tmux
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
