import Foundation

public struct CloudKitSyncLogEntry: Identifiable, Equatable, Sendable {
    public enum Level: String, Sendable {
        case info
        case success
        case warning
        case error

        public var label: String {
            switch self {
            case .info: return "INFO"
            case .success: return "OK"
            case .warning: return "WARN"
            case .error: return "ERR"
            }
        }
    }

    public let id: UUID
    public let timestamp: Date
    public let level: Level
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: Level, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }

    public var formattedLine: String {
        let time = Self.timeFormatter.string(from: timestamp)
        return "[\(time)] [\(level.label)] \(message)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

@MainActor
public final class CloudKitSyncLogStore: ObservableObject {
    public static let shared = CloudKitSyncLogStore()

    @Published public private(set) var entries: [CloudKitSyncLogEntry] = []

    private let maxEntries = 250

    private init() {}

    public func log(_ message: String, level: CloudKitSyncLogEntry.Level = .info) {
        let entry = CloudKitSyncLogEntry(level: level, message: message)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        NSLog("Nucleus iCloud [%@]: %@", level.label, message)
    }

    public func clear() {
        entries.removeAll()
        log("Log cleared", level: .info)
    }
}
