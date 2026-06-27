import NucleusKit
import SwiftUI

struct TerminalWorkspaceView: View {
    @StateObject private var browser = TmuxSessionBrowser()
    @State private var attachedSession: TmuxSession?
    @State private var selectedSessionName: String?
    @State private var attachErrorMessage: String?
    @State private var isPreparingAttach = false
    @State private var isDetaching = false

    var body: some View {
        HStack(spacing: 0) {
            sessionSidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)

            Divider()

            terminalPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            browser.startAutoRefresh()
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
                    Text("Select a session to preview, then take over its display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Detach with the button, F12, or ⌘⇧D — tmux prefix (Ctrl+B) may not work here.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
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
                    Text("Start one in Terminal:\ntmux new -s work")
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

    @ViewBuilder
    private var terminalPane: some View {
        if let attachedSession, let tmuxPath = browser.tmuxPath {
            VStack(spacing: 0) {
                HStack {
                    Label(attachedSession.name, systemImage: "terminal.fill")
                        .font(.headline)
                    if attachedSession.isAttached {
                        Text("detached other clients")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Detach") {
                        detach(from: attachedSession)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDetaching)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
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

                TmuxAttachTerminalView(
                    sessionName: attachedSession.name,
                    tmuxPath: tmuxPath,
                    onDetachHotkey: {
                        detach(from: attachedSession)
                    },
                    onExit: { exitCode in
                        if isDetaching {
                            self.attachedSession = nil
                            self.attachErrorMessage = nil
                            return
                        }
                        let code = TmuxSessionService.normalizedExitCode(exitCode) ?? -1
                        if code != 0 {
                            self.attachErrorMessage =
                                "tmux attach failed (exit \(code)). Try Take Over again or check tmux in Terminal."
                        } else {
                            self.attachErrorMessage = "tmux session ended."
                        }
                        self.attachedSession = nil
                    }
                )
                .id(attachedSession.name)
            }
        } else if attachedSession != nil {
            ContentUnavailableView {
                Label("Could not start tmux attach", systemImage: "exclamationmark.triangle")
            } description: {
                Text("tmux path is unavailable. Click Refresh in the session list.")
            }
        } else if let selectedName = selectedSessionName,
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
            try? await Task.sleep(for: .milliseconds(150))
            attachErrorMessage = nil
            attachedSession = nil
            await browser.refresh()
        }
    }

    private func attach(to session: TmuxSession) {
        selectedSessionName = session.name
        attachErrorMessage = nil
        isPreparingAttach = true

        Task {
            defer { isPreparingAttach = false }
            guard let tmuxPath = browser.tmuxPath ?? TmuxSessionService.resolveTmuxPath() else {
                attachErrorMessage = "tmux path is unavailable."
                return
            }
            await TmuxSessionService.prepareSessionForAttach(sessionName: session.name, tmuxPath: tmuxPath)
            attachedSession = session
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
