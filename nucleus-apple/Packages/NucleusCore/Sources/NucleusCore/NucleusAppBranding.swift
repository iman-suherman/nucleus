import Foundation

public enum NucleusAppBranding {
    public static let displayName = "Nucleus"
    public static let tagline = "Personal Workspace"

    public static let mobileCompanionSummary =
        "Nucleus for phone and tablet is your mobile companion — Dashboard, Notes, Passwords, Bills, and Calendar stay in sync with your computer via cloud sync."

    public struct Feature: Sendable, Identifiable {
        public let title: String
        public let detail: String
        public let icon: String

        public var id: String { title }

        public init(title: String, detail: String, icon: String) {
            self.title = title
            self.detail = detail
            self.icon = icon
        }
    }

    public static let mobileFeatures: [Feature] = [
        Feature(
            title: "Dashboard",
            detail: "Quotes, weather, and workspace insights",
            icon: MobileWorkspaceTab.dashboard.icon
        ),
        Feature(
            title: "Notes",
            detail: "Capture ideas synced across devices",
            icon: MobileWorkspaceTab.notes.icon
        ),
        Feature(
            title: "Passwords",
            detail: "Secure notes for credentials",
            icon: MobileWorkspaceTab.passwords.icon
        ),
        Feature(
            title: "Bills",
            detail: "Track payments and due dates",
            icon: MobileWorkspaceTab.bills.icon
        ),
        Feature(
            title: "Calendar",
            detail: "Upcoming events and meeting links",
            icon: MobileWorkspaceTab.calendar.icon
        ),
    ]
}
