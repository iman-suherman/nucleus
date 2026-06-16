import Foundation

public enum SyncProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case iCloud
    case nucleusCloud
    case googleDrive
    case selfHosted
    case localExport

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .iCloud:
            return "iCloud"
        case .nucleusCloud:
            return "Nucleus Cloud"
        case .googleDrive:
            return "Google Drive"
        case .selfHosted:
            return "Self-Hosted"
        case .localExport:
            return "Local Export"
        }
    }

    public var subtitle: String {
        switch self {
        case .iCloud:
            return "Sync via Apple iCloud and CloudKit."
        case .nucleusCloud:
            return "Cross-platform sync through nucleus-sync.suherman.net."
        case .googleDrive:
            return "Encrypted nucleus.db in a hidden Drive folder."
        case .selfHosted:
            return "Connect to your own sync server."
        case .localExport:
            return "Manual export and import on this Mac."
        }
    }

    public var isAvailableInV1: Bool {
        switch self {
        case .iCloud, .nucleusCloud:
            return true
        case .googleDrive, .selfHosted, .localExport:
            return false
        }
    }
}
