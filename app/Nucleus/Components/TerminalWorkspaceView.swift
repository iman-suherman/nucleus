import NucleusKit
import SwiftUI

struct TerminalWorkspaceView: View {
    @StateObject private var browser = TmuxSessionBrowser()
    @State private var attachedSession: TmuxSession?
    @State private var selectedSessionName: String?

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

            if let errorMessage = browser.errorMessage {
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
                    .disabled(attachedSession?.name == selected.name)

                    if attachedSession?.name == selected.name {
                        Button("Release") {
                            attachedSession = nil
                        }
                        .buttonStyle(.bordered)
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
                        self.attachedSession = nil
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

                TmuxAttachTerminalView(
                    sessionName: attachedSession.name,
                    tmuxPath: tmuxPath,
                    onDetach: {
                        if self.attachedSession?.name == attachedSession.name {
                            self.attachedSession = nil
                        }
                    }
                )
                .id(attachedSession.name)
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

    private func attach(to session: TmuxSession) {
        selectedSessionName = session.name
        attachedSession = session
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
