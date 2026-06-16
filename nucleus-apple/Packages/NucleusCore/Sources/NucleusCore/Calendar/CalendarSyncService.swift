import CalendarKit
import Foundation
import NucleusKit

/// Phase 2: Pull Google Calendar events and feed the native dashboard + reminders.
@MainActor
public final class CalendarSyncService: ObservableObject {
    @Published public private(set) var events: [CalendarEventSummary] = []
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncError: String?

    private let reminderScheduler = MeetingReminderScheduler.shared

    public init() {}

    public func syncEvents(for account: GoogleAccount, cookies: [HTTPCookie]) async {
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        let fetched = await CalendarWebSessionClient.sync(
            account: account,
            cookies: cookies
        )
        events = fetched.sorted { $0.startDate < $1.startDate }

        for event in events where event.startDate > Date() {
            await reminderScheduler.scheduleReminders(for: event)
        }
    }

    public func upcomingEvents(within hours: Int = 24) -> [CalendarEventSummary] {
        let cutoff = Date().addingTimeInterval(TimeInterval(hours * 3600))
        return events.filter { $0.startDate <= cutoff && $0.endDate >= Date() }
    }
}
