import CalendarKit
import Foundation
import NucleusKit

public struct DashboardMeetingReminderPrompt: Identifiable, Equatable, Sendable {
    public let events: [CalendarEventSummary]
    public let kind: MeetingReminderPlanner.Reminder.Kind
    public let startDate: Date

    public var id: String {
        events.map(\.id).sorted().joined(separator: "|")
    }

    public init(
        events: [CalendarEventSummary],
        kind: MeetingReminderPlanner.Reminder.Kind,
        startDate: Date
    ) {
        self.events = events
        self.kind = kind
        self.startDate = startDate
    }

    public func headline(now: Date = Date()) -> String {
        if events.count > 1 {
            return "\(events.count) meetings \(CalendarEventFormatting.timeUntilStartLabel(for: startDate, now: now))"
        }
        return CalendarEventFormatting.meetingStartsInLabel(for: startDate, now: now)
    }

    public var startLabel: String {
        Self.timeFormatter.string(from: startDate)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

@MainActor
public final class MobileMeetingReminderController: ObservableObject {
    public static let shared = MobileMeetingReminderController()

    @Published public private(set) var prompt: DashboardMeetingReminderPrompt?

    private var firedMeetingReminderGroups: [String: Date] = [:]

    private init() {}

    public func checkDueReminders(in events: [CalendarEventSummary], enabled: Bool = true) {
        guard enabled else { return }
        pruneFiredMeetingReminders()
        let due = MeetingReminderPlanner.dueReminders(for: events)
        for reminder in due {
            presentMeetingReminder(reminder.event, in: events, kind: reminder.kind)
        }
    }

    public func presentMeetingReminder(
        _ event: CalendarEventSummary,
        in events: [CalendarEventSummary],
        kind: MeetingReminderPlanner.Reminder.Kind
    ) {
        let grouped = MeetingReminderPlanner.eventsStartingTogether(with: event, in: events)
        guard !grouped.isEmpty else { return }

        let groupKey = MeetingReminderPlanner.alertGroupKey(for: event, in: events)
        guard firedMeetingReminderGroups[groupKey] == nil else { return }

        firedMeetingReminderGroups[groupKey] = event.startDate
        prompt = DashboardMeetingReminderPrompt(
            events: grouped,
            kind: kind,
            startDate: event.startDate
        )
    }

    public func dismissPrompt() {
        prompt = nil
    }

    private func pruneFiredMeetingReminders() {
        let now = Date()
        firedMeetingReminderGroups = firedMeetingReminderGroups.filter { $0.value > now }
    }
}
