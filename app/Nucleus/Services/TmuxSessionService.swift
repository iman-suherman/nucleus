import Foundation

struct TmuxSession: Identifiable, Hashable, Sendable {
    let name: String
    let windowCount: Int
    let isAttached: Bool
    let lastActivity: Date?
    var preview: String

    var id: String { name }
}

enum TmuxSessionError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum TmuxSessionService {
    static func resolveTmuxPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    static func defaultSocketPath() -> String {
        "/private/tmp/tmux-\(getuid())/default"
    }

    /// Shell-quoted value for use inside single-quoted zsh strings.
    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Force-detach all clients on the session, then attach (login zsh for PATH/home).
    static func attachLaunchPlan(sessionName: String, tmuxPath: String) -> (executable: String, args: [String]) {
        let socket = shellSingleQuoted(defaultSocketPath())
        let tmux = shellSingleQuoted(tmuxPath)
        let session = shellSingleQuoted(sessionName)
        let script = """
        unset TMUX TMUX_PANE
        \(tmux) -S \(socket) detach-client -s \(session) 2>/dev/null || true
        exec \(tmux) -S \(socket) attach -d -t \(session)
        """
        return ("/bin/zsh", ["-l", "-c", script])
    }

    /// Normalize wait status (256 → 1) from SwiftTerm / Process termination.
    static func normalizedExitCode(_ code: Int32?) -> Int32? {
        guard let code else { return nil }
        if code > 255 { return code >> 8 }
        return code
    }

    static func enrichedEnvironmentArray() -> [String] {
        enrichedEnvironment().map { "\($0.key)=\($0.value)" }
    }

    static func listSessions() async -> Result<[TmuxSession], TmuxSessionError> {
        guard let tmuxPath = resolveTmuxPath() else {
            return .failure(.message("tmux was not found. Install with Homebrew: brew install tmux"))
        }

        do {
            let output = try await run(
                executable: tmuxPath,
                arguments: [
                    "-S", defaultSocketPath(),
                    "list-sessions",
                    "-F",
                    "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_activity}",
                ]
            )

            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .success([])
            }

            var sessions: [TmuxSession] = []
            for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard let name = parts.first, !name.isEmpty else { continue }

                let windowCount = Int(parts.dropFirst().first ?? "") ?? 0
                let attachedFlag = parts.dropFirst(2).first ?? "0"
                let activityEpoch = TimeInterval(parts.dropFirst(3).first ?? "") ?? 0
                let preview = (try? await capturePane(tmuxPath: tmuxPath, sessionName: name)) ?? ""

                sessions.append(
                    TmuxSession(
                        name: name,
                        windowCount: windowCount,
                        isAttached: attachedFlag == "1",
                        lastActivity: activityEpoch > 0 ? Date(timeIntervalSince1970: activityEpoch) : nil,
                        preview: preview
                    )
                )
            }

            sessions.sort { lhs, rhs in
                let lhsActivity = lhs.lastActivity ?? .distantPast
                let rhsActivity = rhs.lastActivity ?? .distantPast
                if lhsActivity != rhsActivity {
                    return lhsActivity > rhsActivity
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return .success(sessions)
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("no server running") {
                return .success([])
            }
            return .failure(.message(message))
        }
    }

    static func capturePane(tmuxPath: String, sessionName: String) async throws -> String {
        let output = try await run(
            executable: tmuxPath,
            arguments: ["-S", defaultSocketPath(), "capture-pane", "-pt", sessionName, "-S", "-120"]
        )
        return trimPreview(output)
    }

    private static func trimPreview(_ text: String) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let tail = lines.suffix(18)
        return tail.joined(separator: "\n")
    }

    private static func run(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runSync(executable: executable, arguments: arguments))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runSync(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = enrichedEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "TmuxSessionService",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? out : message]
            )
        }

        return out
    }

    private static func enrichedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        environment["HOME"] = home

        let pathEntries = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existing = environment["PATH"] ?? ""
        let merged = (pathEntries + existing.split(separator: ":").map(String.init))
            .uniqued()
            .joined(separator: ":")
        environment["PATH"] = merged
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        return environment
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

@MainActor
final class TmuxSessionBrowser: ObservableObject {
    @Published private(set) var sessions: [TmuxSession] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var tmuxPath: String?

    private var refreshTask: Task<Void, Never>?

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        tmuxPath = TmuxSessionService.resolveTmuxPath()
        let result = await TmuxSessionService.listSessions()
        switch result {
        case .success(let sessions):
            self.sessions = sessions
            self.errorMessage = nil
        case .failure(let error):
            self.sessions = []
            self.errorMessage = error.localizedDescription
        }
    }
}
