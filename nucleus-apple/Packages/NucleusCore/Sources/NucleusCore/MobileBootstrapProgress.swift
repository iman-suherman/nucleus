import Foundation

public enum MobileBootstrapStage: Int, CaseIterable, Identifiable, Sendable {
    case starting
    case checkingICloud
    case notifications
    case loadingBills
    case loadingCalendar
    case importingNotes
    case schedulingReminders
    case finishing

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .starting:
            return "Starting cloud sync"
        case .checkingICloud:
            return "Checking iCloud account"
        case .notifications:
            return "Preparing notifications"
        case .loadingBills:
            return "Loading bills"
        case .loadingCalendar:
            return "Loading calendar"
        case .importingNotes:
            return "Importing notes"
        case .schedulingReminders:
            return "Scheduling reminders"
        case .finishing:
            return "Finishing up"
        }
    }

    public var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }

    public func status(for activeStage: MobileBootstrapStage) -> MobileBootstrapStepStatus {
        if rawValue < activeStage.rawValue {
            return .completed
        }
        if rawValue == activeStage.rawValue {
            return .active
        }
        return .pending
    }
}

public enum MobileBootstrapStepStatus: Sendable {
    case pending
    case active
    case completed
}
