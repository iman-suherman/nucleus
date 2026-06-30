import EventKit
import Foundation
import NucleusKit

public enum CalendarAccessState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public enum EventKitCalendarClient {
    public static func currentAccessState() -> CalendarAccessState {
        mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
    }

    public static func requestAccess() async -> (state: CalendarAccessState, errorMessage: String?) {
        await requestAccessOnMainActor()
    }

    @MainActor
    private static func requestAccessOnMainActor() async -> (state: CalendarAccessState, errorMessage: String?) {
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToEvents()
            let state = granted ? CalendarAccessState.authorized : .denied
            return (state, granted ? nil : "Calendar access was not granted.")
        } catch {
            return (.denied, error.localizedDescription)
        }
    }

    public static func fetchUpcomingEvents(
        daysAhead: Int = 14,
        now: Date = Date()
    ) -> [CalendarEventSummary] {
        guard hasReadAccess() else { return [] }

        let store = EKEventStore()
        let calendar = Calendar.current
        let start = now
        let end = calendar.date(byAdding: .day, value: daysAhead, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        return events
            .compactMap { mapEvent($0) }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func hasReadAccess() -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    private static func mapAuthorizationStatus(_ status: EKAuthorizationStatus) -> CalendarAccessState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .fullAccess:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .writeOnly:
            return .denied
        @unknown default:
            return .notDetermined
        }
    }

    private static func mapEvent(_ event: EKEvent) -> CalendarEventSummary? {
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        guard !CalendarJunkFilter.isCalendarChromeTitle(title) else { return nil }
        guard let startDate = event.startDate, let endDate = event.endDate else { return nil }

        let location = event.location ?? ""
        let notes = event.notes ?? ""
        let meetingLink = MeetingLinkExtractor.extract(
            url: event.url,
            description: notes,
            location: location
        )

        let calendarLabel = event.calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountEmail = calendarLabel.isEmpty ? SystemCalendarIdentity.accountEmail : calendarLabel
        let stableID = event.eventIdentifier ?? UUID().uuidString
        let id = "\(SystemCalendarIdentity.accountID.uuidString)-\(stableID)-\(Int(startDate.timeIntervalSince1970))"

        let attendees = (event.attendees ?? []).compactMap { attendee -> String? in
            let name = attendee.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty { return name }
            return attendee.url.absoluteString
        }

        return CalendarEventSummary(
            id: id,
            accountID: SystemCalendarIdentity.accountID,
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location,
            attendees: attendees,
            meetingLink: meetingLink,
            accountEmail: accountEmail
        )
    }
}
