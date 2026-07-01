import CalendarKit
import NucleusCore
import NucleusKit
import SwiftUI

public struct DashboardCalendarScheduleCard: View {
    public static let previewMeetingCount = 5

    let birthdays: [CalendarEventSummary]
    let events: [CalendarEventSummary]
    let isSyncing: Bool
    var onShowMore: (() -> Void)?

    public init(
        birthdays: [CalendarEventSummary],
        events: [CalendarEventSummary],
        isSyncing: Bool,
        onShowMore: (() -> Void)? = nil
    ) {
        self.birthdays = birthdays
        self.events = events
        self.isSyncing = isSyncing
        self.onShowMore = onShowMore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Schedule", systemImage: "calendar")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)

                Spacer(minLength: 0)

                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            CalendarScheduleListView(
                birthdays: birthdays,
                events: events,
                meetingLimit: Self.previewMeetingCount
            )

            if let onShowMore, hiddenMeetingCount > 0 {
                Button {
                    onShowMore()
                } label: {
                    HStack {
                        Text("Show more · \(hiddenMeetingCount) more meeting\(hiddenMeetingCount == 1 ? "" : "s")")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hiddenMeetingCount: Int {
        max(0, events.count - Self.previewMeetingCount)
    }
}

public struct DashboardUpcomingBirthdaysCard: View {
    let birthdays: [CalendarEventSummary]

    public init(birthdays: [CalendarEventSummary]) {
        self.birthdays = birthdays
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(headerTitle, systemImage: "birthday.cake.fill")
                .font(.headline)
                .foregroundStyle(.pink)
                .symbolRenderingMode(.multicolor)

            Text("Next \(MobileDashboardCalendarHelpers.dashboardBirthdayHorizonDays) days")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(birthdays) { birthday in
                    CalendarBirthdayEventRow(birthday: birthday)
                    if birthday.id != birthdays.last?.id {
                        Divider().padding(.leading, 82)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var headerTitle: String {
        birthdays.count == 1 ? "Upcoming birthday" : "Upcoming birthdays"
    }
}

public struct DashboardNextMeetingCard: View {
    let group: MeetingReminderPlanner.UpcomingMeetingGroup

    public init(group: MeetingReminderPlanner.UpcomingMeetingGroup) {
        self.group = group
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let event = group.events[0]
            VStack(alignment: .leading, spacing: 10) {
                Label("Next meeting", systemImage: "video.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)
                    .symbolRenderingMode(.multicolor)

                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))

                    Text(CalendarEventFormatting.timeUntilStartWithDurationLabel(for: event, now: context.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)

                    Text(CalendarEventFormatting.scheduleTimeAndDurationLabel(for: event))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if group.events.count > 1 {
                        Text("\(group.events.count) overlapping invites at this time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(group.events) { invite in
                        HStack(spacing: 8) {
                            if !invite.accountEmail.isEmpty {
                                CalendarAccountBadge(email: invite.accountEmail)
                            }
                            Spacer(minLength: 0)
                            if let link = invite.meetingLink, let url = URL(string: link) {
                                Link("Join", destination: url)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
