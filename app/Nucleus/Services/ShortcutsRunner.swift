import Foundation

enum ShortcutsRunner {
    static func runShortcut(named name: String) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name]

                let pipe = Pipe()
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(()))
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let message = String(data: data, encoding: .utf8) ?? "Shortcut failed."
                        continuation.resume(returning: .failure(ShortcutError.failed(message)))
                    }
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    enum ShortcutError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
