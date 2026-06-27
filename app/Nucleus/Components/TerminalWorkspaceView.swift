import NucleusKit
import SwiftUI

struct TerminalWorkspaceView: View {
    @StateObject private var browser = TmuxSessionBrowser()
    @State private var activeSession: TmuxSession?
    @State private var terminalErrorMessage: String?
    @State private var isPreparingSession = false
    @State private var isDetaching = false
    @State private var showNewSessionSheet = false
    @State private var newSessionName = ""

    var body: some View {
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
                if activeSession == nil {
                    ContentUnavailableView {
                        Label("No active terminal", systemImage: "terminal")
                    } description: {
                        Text("Start a new tmux session here. Use Terminal.app to attach to existing sessions listed above.")
                    } actions: {
                        Button("New Session") {
                            prepareNewSessionSheet()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let tmuxPath = browser.tmuxPath {
                    terminalLayer(tmuxPath: tmuxPath)
                } else if activeSession != nil {
                    ContentUnavailableView {
                        Label("tmux unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Install tmux with Homebrew: brew install tmux")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showNewSessionSheet) {
            newSessionSheet
        }
        .onAppear {
            browser.startAutoRefresh()
        }
        .onDisappear {
            browser.stopAutoRefresh()
            if let session = activeSession {
                let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath()
                if let tmuxPath {
                    Task {
                        await TmuxSessionService.detachSession(sessionName: session.name, tmuxPath: tmuxPath)
                    }
                }
            }
            activeSession = nil
        }
    }

    private var commandExampleName: String {
        activeSession?.name ?? "<name>"
    }

    private var terminalTopBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    commandLine(title: "Attach (Terminal.app)", command: TmuxSessionService.attachCommand(sessionName: commandExampleName))
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
                    .disabled(isPreparingSession || activeSession != nil)

                    if activeSession != nil {
                        Button("Detach") {
                            detachActiveSession()
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Active tmux sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if browser.sessions.isEmpty {
                    Text("none")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                } else {
                    Text(activeSessionSummaries)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let activeSession {
                Text("Live in Nucleus: \(activeSession.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var activeSessionSummaries: String {
        browser.sessions
            .map { session in
                var label = "\(session.name) (\(session.windowCount)w"
                if session.isAttached {
                    label += ", attached"
                }
                if activeSession?.name == session.name {
                    label += ", live here"
                }
                label += ")"
                return label
            }
            .joined(separator: "  ·  ")
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
            Text("New tmux session")
                .font(.title3.bold())

            Text("Opens a fresh session in Nucleus. Existing sessions can be attached from Terminal.app using the command above.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Session name", text: $newSessionName)
                .textFieldStyle(.roundedBorder)

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
                    startNewSession(named: newSessionName)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isPreparingSession)
            }
        }
        .padding(24)
        .frame(minWidth: 380)
    }

    @ViewBuilder
    private func terminalLayer(tmuxPath: String) -> some View {
        VStack(spacing: 0) {
            TmuxAttachTerminalView(
                activeSessionName: activeSession?.name,
                tmuxPath: tmuxPath,
                onDetachHotkey: {
                    detachActiveSession()
                },
                onExit: { exitCode in
                    if isDetaching {
                        self.activeSession = nil
                        self.terminalErrorMessage = nil
                        return
                    }
                    let code = TmuxSessionService.normalizedExitCode(exitCode) ?? -1
                    if code != 0 {
                        self.terminalErrorMessage =
                            "tmux session failed (exit \(code)). Try a different session name."
                    }
                    self.activeSession = nil
                    Task { await browser.refresh() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: activeSession == nil ? 0 : .infinity)
            .clipped()
            .opacity(activeSession == nil ? 0 : 1)
            .allowsHitTesting(activeSession != nil)
            .accessibilityHidden(activeSession == nil)
        }
        .allowsHitTesting(activeSession != nil)
    }

    private func detachActiveSession() {
        detach(from: activeSession)
    }

    private func detach(from session: TmuxSession?) {
        guard let session, !isDetaching else { return }

        Task {
            isDetaching = true
            defer { isDetaching = false }

            guard let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath() else {
                terminalErrorMessage = "tmux path is unavailable."
                activeSession = nil
                return
            }

            await TmuxSessionService.detachSession(sessionName: session.name, tmuxPath: tmuxPath)
            terminalErrorMessage = nil
            activeSession = nil
            await browser.refresh()
        }
    }

    private func prepareNewSessionSheet() {
        terminalErrorMessage = nil
        newSessionName = TmuxSessionService.suggestNewSessionName(
            existingSessionNames: browser.sessions.map(\.name)
        )
        showNewSessionSheet = true
    }

    private func startNewSession(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        terminalErrorMessage = nil

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
            activeSession = TmuxSession(
                name: name,
                windowCount: 1,
                isAttached: false,
                lastActivity: Date(),
                preview: ""
            )
        }
    }
}
