import NucleusKit
import SwiftUI

struct TerminalWorkspaceView: View {
    @StateObject private var browser = TmuxSessionBrowser()
    @State private var attachedSession: TmuxSession?
    @State private var selectedSessionName: String?
    @State private var attachErrorMessage: String?
    @State private var isPreparingAttach = false
    @State private var isDetaching = false
    @State private var isCreatingNewSession = false
    @State private var showNewSessionSheet = false
    @State private var newSessionName = ""

    var body: some View {
        HStack(spacing: 0) {
            sessionSidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)

            Divider()

            terminalPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showNewSessionSheet) {
            newSessionSheet
        }
        .onAppear {
            browser.startAutoRefresh()
        }
        .onChange(of: attachedSession?.name) { _, sessionName in
            if sessionName == nil {
                browser.startAutoRefresh()
            } else {
                browser.stopAutoRefresh()
            }
        }
        .onDisappear {
            browser.stopAutoRefresh()
            if let session = attachedSession {
                let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath()
                if let tmuxPath {
                    Task {
                        await TmuxSessionService.detachSession(sessionName: session.name, tmuxPath: tmuxPath)
                    }
                }
            }
            attachedSession = nil
        }
    }

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("tmux sessions")
                        .font(.headline)
                    Text("Select a session to preview, take over, or start a new one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Detach with the button, F12, or ⌘⇧D — tmux prefix (Ctrl+B) may not work here.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    prepareNewSessionSheet()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(isPreparingAttach || attachedSession != nil)
                Button {
                    Task { await browser.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(browser.isRefreshing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if let errorMessage = browser.errorMessage ?? attachErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if browser.sessions.isEmpty && browser.errorMessage == nil {
                ContentUnavailableView {
                    Label("No tmux sessions", systemImage: "terminal")
                } description: {
                    Text("Click New to start a tmux session here, or run tmux new -s work in Terminal.")
                } actions: {
                    Button("New Session") {
                        prepareNewSessionSheet()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedSessionName) {
                    ForEach(browser.sessions) { session in
                        TmuxSessionRow(
                            session: session,
                            isAttachedHere: attachedSession?.name == session.name
                        )
                        .tag(session.name as String?)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSessionName = session.name
                        }
                    }
                }
                .listStyle(.inset)
            }

            if let selected = browser.sessions.first(where: { $0.name == selectedSessionName }) {
                HStack {
                    Button("Take Over") {
                        attach(to: selected)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(attachedSession?.name == selected.name || isPreparingAttach)

                    if attachedSession?.name == selected.name {
                        Button("Release") {
                            detach(from: selected)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDetaching)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var newSessionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New tmux session")
                .font(.title3.bold())

            Text("Creates a new session and opens it here. It will appear in the session list after you detach.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Session name", text: $newSessionName)
                .textFieldStyle(.roundedBorder)

            if let attachErrorMessage {
                Text(attachErrorMessage)
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
                .disabled(isPreparingAttach)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    @ViewBuilder
    private var terminalPane: some View {
        ZStack {
            if attachedSession == nil {
                if let selectedName = selectedSessionName,
                   let session = browser.sessions.first(where: { $0.name == selectedName }) {
                    previewPane(for: session)
                } else {
                    ContentUnavailableView {
                        Label("No session selected", systemImage: "arrow.left")
                    } description: {
                        Text("Choose a tmux session on the left, then click Take Over to attach interactively inside Nucleus.")
                    }
                }
            }

            if let tmuxPath = browser.tmuxPath {
                attachedTerminalLayer(tmuxPath: tmuxPath)
            } else if attachedSession != nil {
                ContentUnavailableView {
                    Label("Could not start tmux attach", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("tmux path is unavailable. Click Refresh in the session list.")
                }
            }
        }
    }

    @ViewBuilder
    private func attachedTerminalLayer(tmuxPath: String) -> some View {
        VStack(spacing: 0) {
            if attachedSession != nil {
                HStack {
                    Label(attachedSession?.name ?? "tmux", systemImage: "terminal.fill")
                        .font(.headline)
                    if isCreatingNewSession {
                        Text("new session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if attachedSession?.isAttached == true {
                        Text("detached other clients")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let session = attachedSession {
                        Button("Detach") {
                            detach(from: session)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDetaching)
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

                Text("Use Detach, F12, or ⌘⇧D instead of tmux prefix + d.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                if let attachErrorMessage {
                    Text(attachErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08))
                }
            }

            TmuxAttachTerminalView(
                activeSessionName: attachedSession?.name,
                createNewSession: isCreatingNewSession,
                tmuxPath: tmuxPath,
                onDetachHotkey: {
                    if let session = attachedSession {
                        detach(from: session)
                    }
                },
                onExit: { exitCode in
                    if isDetaching {
                        self.attachedSession = nil
                        self.attachErrorMessage = nil
                        self.isCreatingNewSession = false
                        return
                    }
                    let code = TmuxSessionService.normalizedExitCode(exitCode) ?? -1
                    if code != 0 {
                        self.attachErrorMessage =
                            "tmux session failed (exit \(code)). Try again or check tmux in Terminal."
                    } else {
                        self.attachErrorMessage = "tmux session ended."
                    }
                    self.attachedSession = nil
                    self.isCreatingNewSession = false
                    Task { await browser.refresh() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: attachedSession == nil ? 0 : .infinity)
            .clipped()
            .opacity(attachedSession == nil ? 0 : 1)
            .allowsHitTesting(attachedSession != nil)
            .accessibilityHidden(attachedSession == nil)
        }
        .allowsHitTesting(attachedSession != nil)
    }

    private func previewPane(for session: TmuxSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name)
                        .font(.title3.bold())
                    HStack(spacing: 12) {
                        Label("\(session.windowCount) windows", systemImage: "square.grid.2x2")
                        if session.isAttached {
                            Label("attached elsewhere", systemImage: "link")
                                .foregroundStyle(.orange)
                        }
                        if let lastActivity = session.lastActivity {
                            Text(NucleusFormatters.relativeDate.localizedString(for: lastActivity, relativeTo: Date()))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
                Spacer()
                Button("Take Over") {
                    attach(to: session)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparingAttach)
            }

            ScrollView {
                Text(session.preview.isEmpty ? "No preview available." : session.preview)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
                    .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(Color(red: 0.86, green: 0.92, blue: 0.86))
            }
        }
        .padding(20)
    }

    private func detach(from session: TmuxSession?) {
        guard let session, !isDetaching else { return }

        Task {
            isDetaching = true
            defer { isDetaching = false }

            guard let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath() else {
                attachErrorMessage = "tmux path is unavailable."
                attachedSession = nil
                return
            }

            await TmuxSessionService.detachSession(sessionName: session.name, tmuxPath: tmuxPath)
            attachErrorMessage = nil
            attachedSession = nil
            isCreatingNewSession = false
            await browser.refresh()
            browser.startAutoRefresh()
        }
    }

    private func prepareNewSessionSheet() {
        attachErrorMessage = nil
        newSessionName = TmuxSessionService.suggestNewSessionName(
            existingSessionNames: browser.sessions.map(\.name)
        )
        showNewSessionSheet = true
    }

    private func startNewSession(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        attachErrorMessage = nil

        if let validationError = TmuxSessionService.validateSessionName(name) {
            attachErrorMessage = validationError
            return
        }

        isPreparingAttach = true
        Task {
            defer { isPreparingAttach = false }
            guard let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath() else {
                attachErrorMessage = "tmux path is unavailable."
                return
            }
            if await TmuxSessionService.validateSessionExists(sessionName: name, tmuxPath: tmuxPath) == nil {
                attachErrorMessage = "Session \"\(name)\" already exists. Choose another name or use Take Over."
                return
            }

            showNewSessionSheet = false
            selectedSessionName = name
            isCreatingNewSession = true
            attachedSession = TmuxSession(
                name: name,
                windowCount: 1,
                isAttached: false,
                lastActivity: Date(),
                preview: ""
            )
            browser.stopAutoRefresh()
        }
    }

    private func attach(to session: TmuxSession) {
        selectedSessionName = session.name
        attachErrorMessage = nil
        isCreatingNewSession = false
        isPreparingAttach = true

        Task {
            defer { isPreparingAttach = false }
            guard let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath() else {
                attachErrorMessage = "tmux path is unavailable."
                return
            }
            if let validationError = await TmuxSessionService.validateSessionExists(
                sessionName: session.name,
                tmuxPath: tmuxPath
            ) {
                attachErrorMessage = validationError
                return
            }
            await TmuxSessionService.prepareSessionForAttach(sessionName: session.name, tmuxPath: tmuxPath)
            attachErrorMessage = nil
            attachedSession = session
            browser.stopAutoRefresh()
        }
    }
}

private struct TmuxSessionRow: View {
    let session: TmuxSession
    let isAttachedHere: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.name)
                    .font(.headline)
                Spacer()
                if isAttachedHere {
                    Text("live")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.18), in: Capsule())
                } else if session.isAttached {
                    Text("attached")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                }
            }

            Text("\(session.windowCount) window\(session.windowCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !session.preview.isEmpty {
                Text(session.preview.split(separator: "\n").last.map(String.init) ?? session.preview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
