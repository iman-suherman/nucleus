import CalendarKit
import NucleusCore
import NucleusKit
import SwiftUI

public struct CalendarScheduleListView: View {
    let birthdays: [CalendarEventSummary]
    let events: [CalendarEventSummary]
    let meetingLimit: Int?

    public init(
        birthdays: [CalendarEventSummary],
        events: [CalendarEventSummary],
        meetingLimit: Int? = nil
    ) {
        self.birthdays = birthdays
        self.events = events
        self.meetingLimit = meetingLimit
    }

    private var displayedEvents: [CalendarEventSummary] {
        guard let meetingLimit else { return events }
        return Array(events.prefix(meetingLimit))
    }

    public var hiddenMeetingCount: Int {
        max(0, events.count - displayedEvents.count)
    }

    public var body: some View {
        if birthdays.isEmpty && displayedEvents.isEmpty {
            Text("No upcoming events. Pull to refresh after syncing from your computer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    if !birthdays.isEmpty {
                        CalendarScheduleSectionHeader(title: "Birthdays", systemImage: "birthday.cake.fill", tint: .pink)
                    }

                    ForEach(birthdays) { birthday in
                        CalendarBirthdayEventRow(birthday: birthday)
                        if !displayedEvents.isEmpty || birthday.id != birthdays.last?.id {
                            Divider().padding(.leading, 82)
                        }
                    }

                    if !birthdays.isEmpty && !displayedEvents.isEmpty {
                        CalendarScheduleSectionHeader(title: "Meetings", systemImage: "calendar", tint: .primary)
                            .padding(.top, 8)
                    }

                    ForEach(displayedEvents) { event in
                        CalendarScheduleEventRow(event: event, now: context.date)
                        if event.id != displayedEvents.last?.id {
                            Divider().padding(.leading, 82)
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

public struct CalendarBirthdayEventRow: View {
    let birthday: CalendarEventSummary

    public init(birthday: CalendarEventSummary) {
        self.birthday = birthday
    }

    public var body: some View {
        let name = BirthdayCalendarFormatting.displayName(from: birthday.title)

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "birthday.cake.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                Text(dayLabel(for: birthday.startDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(name) birthday")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if !birthday.accountEmail.isEmpty {
                    CalendarAccountBadge(email: birthday.accountEmail)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        return CalendarScheduleEventRow.dayFormatter.string(from: date)
    }
}

public struct CalendarScheduleEventRow: View {
    let event: CalendarEventSummary
    let now: Date

    public init(event: CalendarEventSummary, now: Date = Date()) {
        self.event = event
        self.now = now
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(CalendarEventFormatting.shortTime(for: event.startDate))
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text(CalendarEventFormatting.shortTime(for: event.endDate))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(dayLabel(for: event.startDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(CalendarEventFormatting.timeUntilStartWithDurationLabel(for: event, now: now))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)

                Text(CalendarEventFormatting.scheduleTimeAndDurationLabel(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !event.accountEmail.isEmpty {
                    CalendarAccountBadge(email: event.accountEmail)
                }

                if !event.location.isEmpty, event.meetingLink == nil {
                    Text(event.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let link = event.meetingLink, let url = URL(string: link) {
                    Link(destination: url) {
                        Label("Join video call", systemImage: "video.fill")
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        return Self.dayFormatter.string(from: date)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()
}

public struct CalendarAccountBadge: View {
    let email: String

    public init(email: String) {
        self.email = email
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "envelope.fill")
                .font(.caption2)
            Text(email)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.orange)
    }
}

private struct CalendarScheduleSectionHeader: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .symbolRenderingMode(.multicolor)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}
