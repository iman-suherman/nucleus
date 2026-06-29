import Foundation

struct TmuxSession: Identifiable, Hashable, Sendable {
    let name: String
    let windowCount: Int
    let isAttached: Bool
    var preview: String

    var id: String { name }

    var displayName: String {
        TmuxSessionService.displayName(for: name)
    }
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

    static func attachArguments(sessionName: String) -> [String] {
        [
            "-S", defaultSocketPath(),
            "attach", "-d", "-t", attachTarget(for: sessionName),
        ]
    }

    /// Isolated tmux attach via env -i so no GUI variables leak into the client.
    static func attachLaunchPlan(sessionName: String, tmuxPath: String) -> (executable: String, args: [String]) {
        launchPlan(
            tmuxPath: tmuxPath,
            tmuxArguments: ["-S", defaultSocketPath(), "attach", "-d", "-t", attachTarget(for: sessionName)]
        )
    }

    static func newSessionLaunchPlan(sessionName: String, tmuxPath: String) -> (executable: String, args: [String]) {
        let startDir = sessionStartupDirectory()
        let shell = attachEnvironment()["SHELL"] ?? "/bin/zsh"
        let startupCommand = "ls -l; exec \(shellQuote(shell)) -l"
        return launchPlan(
            tmuxPath: tmuxPath,
            tmuxArguments: [
                "-S", defaultSocketPath(),
                "new-session", "-s", sessionName,
                "-c", startDir,
                shell, "-lc", startupCommand,
            ]
        )
    }

    /// Working directory for new tmux sessions: ~/src when it exists, otherwise ~.
    static func sessionStartupDirectory() -> String {
        let home = defaultHomeDirectory()
        let src = URL(fileURLWithPath: home).appendingPathComponent("src", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return src.path
        }
        return home
    }

    private static func launchPlan(tmuxPath: String, tmuxArguments: [String]) -> (executable: String, args: [String]) {
        var args = ["-i"]
        for (key, value) in attachEnvironment().sorted(by: { $0.key < $1.key }) {
            args.append("\(key)=\(value)")
        }
        args.append(tmuxPath)
        args.append(contentsOf: tmuxArguments)
        return ("/usr/bin/env", args)
    }

    static func suggestNewSessionName(existingSessionNames: [String]) -> String {
        let existing = Set(existingSessionNames)
        let base = "nucleus"
        if !existing.contains(base) {
            return base
        }
        for index in 2...999 {
            let candidate = "\(base)-\(index)"
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "\(base)-\(Int(Date().timeIntervalSince1970))"
    }

    static func validateSessionName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Session name is required."
        }
        if trimmed.count > 64 {
            return "Session name must be 64 characters or fewer."
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use letters, numbers, dots, hyphens, or underscores only."
        }
        return nil
    }

    static func validateSessionExists(sessionName: String, tmuxPath: String) async -> String? {
        let target = attachTarget(for: sessionName)
        do {
            _ = try await run(
                executable: tmuxPath,
                arguments: ["-S", defaultSocketPath(), "has-session", "-t", target]
            )
            return nil
        } catch {
            return "Session \"\(target)\" was not found on the tmux server."
        }
    }

    /// Detach other tmux clients so Nucleus can attach to the session.
    static func prepareSessionForAttach(sessionName: String, tmuxPath: String) async {
        let target = attachTarget(for: sessionName)
        _ = try? await run(
            executable: tmuxPath,
            arguments: ["-S", defaultSocketPath(), "detach-client", "-s", target]
        )
    }

    /// Detach Nucleus from a session without relying on tmux prefix keys (Ctrl+B often fails in embedded terminals).
    static func detachSession(sessionName: String, tmuxPath: String) async {
        let target = attachTarget(for: sessionName)
        _ = try? await run(
            executable: tmuxPath,
            arguments: ["-S", defaultSocketPath(), "detach-client", "-s", target]
        )
    }

    /// Environment for embedded terminal attach — full GUI env breaks tmux attach (exit 1).
    static func attachEnvironmentArray() -> [String] {
        attachEnvironment().map { "\($0.key)=\($0.value)" }
    }

    static func defaultHomeDirectory() -> String {
        attachEnvironment()["HOME"] ?? NSHomeDirectory()
    }

    private static let attachEnvironmentKeys = [
        "HOME", "USER", "LOGNAME", "SHELL", "PATH", "TERM", "LANG", "LC_ALL", "LC_CTYPE",
        "TMPDIR", "SSH_AUTH_SOCK", "XDG_RUNTIME_DIR",
    ]

    private static func attachEnvironment() -> [String: String] {
        let passwd = getpwuid(getuid())
        let home = passwd.map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let user = passwd.map { String(cString: $0.pointee.pw_name) } ?? NSUserName()
        let source = ProcessInfo.processInfo.environment

        var environment: [String: String] = [
            "HOME": home,
            "USER": user,
            "LOGNAME": user,
            "SHELL": source["SHELL"] ?? "/bin/zsh",
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "xterm-256color",
            "LANG": source["LANG"] ?? "en_US.UTF-8",
        ]

        for key in attachEnvironmentKeys {
            guard key != "HOME", key != "USER", key != "LOGNAME", key != "SHELL", key != "PATH", key != "TERM", key != "LANG" else {
                continue
            }
            if let value = source[key], !value.isEmpty {
                environment[key] = value
            }
        }

        return environment
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

    static func attachCommand(sessionName: String = "<name>") -> String {
        guard sessionName != "<name>" else {
            return "tmux -S \(defaultSocketPath()) attach -d -t <name>"
        }
        return "tmux -S \(defaultSocketPath()) attach -d -t \(shellQuote(sessionName))"
    }

    /// Use from an embedded Nucleus terminal (already inside tmux) to avoid nested-session warnings.
    static func attachCommandFromEmbeddedTerminal(sessionName: String) -> String {
        let socket = shellQuote(defaultSocketPath())
        let target = shellQuote(sessionName)
        return "env -u TMUX -u TMUX_PANE tmux -S \(socket) attach -d -t \(target)"
    }

    /// Short label for tmux sessions named `{project}_{major}_{minor}` or `{project}_{major}_{minor}_{timestamp}`.
    static func displayName(for sessionName: String) -> String {
        if let range = sessionName.range(of: #"_\d+_\d+(_\d+)?$"#, options: .regularExpression) {
            return String(sessionName[..<range.lowerBound])
        }
        return sessionName
    }

    /// Target for `tmux attach -t` — always the exact session name from `list-sessions`.
    static func attachTarget(for sessionName: String) -> String {
        sessionName
    }

    /// Kill a tmux session directly without attaching through the embedded terminal.
    static func killSession(sessionName: String, tmuxPath: String) async -> String? {
        let target = attachTarget(for: sessionName)
        let socket = defaultSocketPath()

        _ = try? await run(
            executable: tmuxPath,
            arguments: ["-S", socket, "detach-client", "-s", target]
        )

        do {
            _ = try await run(
                executable: tmuxPath,
                arguments: ["-S", socket, "kill-session", "-t", target]
            )
            return nil
        } catch {
            let message = (error as NSError).localizedDescription
            let lower = message.lowercased()
            if lower.contains("can't find session") || lower.contains("no session") {
                return nil
            }
            return message.isEmpty ? "tmux kill-session failed." : message
        }
    }

    /// Attach in an embedded terminal, send `exit`, then ensure the session is gone.
    static func destroyCommandFromEmbeddedTerminal(sessionName: String) -> String {
        let socket = shellQuote(defaultSocketPath())
        let target = shellQuote(sessionName)
        return "env -u TMUX -u TMUX_PANE tmux -S \(socket) kill-session -t \(target)"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func detachCommand() -> String {
        "tmux -S \(defaultSocketPath()) detach-client"
    }

    static func newSessionCommand(sessionName: String = "<name>") -> String {
        let dir = sessionStartupDirectory()
        return "tmux -S \(defaultSocketPath()) new-session -s \(sessionName) -c \(shellQuote(dir))"
    }

    static func shellLaunchPlan() -> (executable: String, args: [String]) {
        shellCommandLaunchPlan(nil)
    }

    static func shellCommandLaunchPlan(_ command: String?) -> (executable: String, args: [String]) {
        let shell = attachEnvironment()["SHELL"] ?? "/bin/zsh"
        var args = ["-i"]
        for (key, value) in attachEnvironment().sorted(by: { $0.key < $1.key }) {
            args.append("\(key)=\(value)")
        }
        args.append(shell)
        if let command, !command.isEmpty {
            args.append("-lc")
            args.append(command)
        } else {
            args.append("-l")
        }
        return ("/usr/bin/env", args)
    }

    static func listSessions(includePreviews: Bool = false) async -> Result<[TmuxSession], TmuxSessionError> {
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
                    "#{session_name}\t#{session_windows}\t#{session_attached}",
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
                let preview = includePreviews
                    ? ((try? await capturePane(tmuxPath: tmuxPath, sessionName: name)) ?? "")
                    : ""

                sessions.append(
                    TmuxSession(
                        name: name,
                        windowCount: windowCount,
                        isAttached: attachedFlag == "1",
                        preview: preview
                    )
                )
            }

            sessions.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            return .success(sessions)
        } catch {
            let message = error.localizedDescription
            if isAbsentTmuxServerError(message) {
                return .success([])
            }
            return .failure(.message(message))
        }
    }

    static func capturePane(tmuxPath: String, sessionName: String) async throws -> String {
        let output = try await run(
            executable: tmuxPath,
            arguments: ["-S", defaultSocketPath(), "capture-pane", "-pt", attachTarget(for: sessionName), "-S", "-120"]
        )
        return trimPreview(output)
    }

    /// tmux returns different messages when the server was never started vs idle with no sessions.
    private static func isAbsentTmuxServerError(_ message: String) -> Bool {
        let lower = message.localizedLowercase
        return lower.contains("no server running")
            || lower.contains("no such file or directory")
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
    static let shared = TmuxSessionBrowser()

    private static let autoRefreshInterval: Duration = .seconds(15)

    @Published private(set) var sessions: [TmuxSession] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var tmuxPath: String?
    /// Sidebar badge only — updated when session count changes, not on attach/window churn.
    @Published private(set) var badgeSessionCount: Int = 0

    var activeSessionCount: Int {
        badgeSessionCount
    }

    private var refreshTask: Task<Void, Never>?
    private var isRefreshInFlight = false
    private var autoRefreshSuspended = false

    private init() {}

    static func applyDisplayOrder(sessions: [TmuxSession], savedOrder: [String]) -> [TmuxSession] {
        let byName = Dictionary(uniqueKeysWithValues: sessions.map { ($0.name, $0) })
        var ordered: [TmuxSession] = []
        var seen = Set<String>()

        for name in savedOrder {
            guard let session = byName[name] else { continue }
            ordered.append(session)
            seen.insert(name)
        }

        let newcomers = sessions
            .filter { !seen.contains($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        ordered.append(contentsOf: newcomers)
        return ordered
    }

    func moveSession(_ draggedName: String, before targetName: String) {
        guard draggedName != targetName else { return }

        var order = sessions.map(\.name)
        guard order.contains(draggedName), order.contains(targetName) else { return }

        order.removeAll { $0 == draggedName }
        guard let targetIndex = order.firstIndex(of: targetName) else { return }
        order.insert(draggedName, at: targetIndex)
        applySessionOrder(order)
    }

    func moveSessionToEnd(_ draggedName: String) {
        var order = sessions.map(\.name)
        guard order.contains(draggedName) else { return }
        order.removeAll { $0 == draggedName }
        order.append(draggedName)
        applySessionOrder(order)
    }

    private func applySessionOrder(_ order: [String]) {
        let byName = Dictionary(uniqueKeysWithValues: sessions.map { ($0.name, $0) })
        sessions = order.compactMap { byName[$0] }
        AppSettings.shared.tmuxSessionOrder = sessions.map(\.name)
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.autoRefreshSuspended != true {
                    await self?.refresh()
                }
                try? await Task.sleep(for: Self.autoRefreshInterval)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        autoRefreshSuspended = false
    }

    func setAutoRefreshSuspended(_ suspended: Bool) {
        autoRefreshSuspended = suspended
    }

    func refresh(manual: Bool = false) async {
        guard !isRefreshInFlight else { return }
        isRefreshInFlight = true
        if manual {
            isRefreshing = true
        }
        defer {
            isRefreshInFlight = false
            if manual {
                isRefreshing = false
            }
        }

        let resolvedPath = TmuxSessionService.resolveTmuxPath()
        if tmuxPath != resolvedPath {
            tmuxPath = resolvedPath
        }

        let result = await TmuxSessionService.listSessions(includePreviews: false)
        switch result {
        case .success(let sessions):
            let ordered = Self.applyDisplayOrder(
                sessions: sessions,
                savedOrder: AppSettings.shared.tmuxSessionOrder
            )
            let orderNames = ordered.map(\.name)

            if Self.listContentEqual(ordered, self.sessions), errorMessage == nil {
                return
            }

            self.sessions = ordered
            if badgeSessionCount != ordered.count {
                badgeSessionCount = ordered.count
            }
            if AppSettings.shared.tmuxSessionOrder != orderNames {
                AppSettings.shared.tmuxSessionOrder = orderNames
            }
            if errorMessage != nil {
                errorMessage = nil
            }
        case .failure(let error):
            let message = error.localizedDescription
            if sessions.isEmpty, errorMessage == message {
                return
            }
            self.sessions = []
            self.errorMessage = message
            if badgeSessionCount != 0 {
                badgeSessionCount = 0
            }
        }
    }

    private static func listContentEqual(_ lhs: [TmuxSession], _ rhs: [TmuxSession]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            if left.name != right.name
                || left.windowCount != right.windowCount
                || left.isAttached != right.isAttached {
                return false
            }
        }
        return true
    }
}
