import AppKit
import CalendarKit
import NucleusKit
import SwiftUI

struct DashboardCalendarSchedulePanel: View {
    let events: [CalendarEventSummary]
    let isSyncing: Bool
    let accessState: CalendarAccessState
    let hasBirthdayCalendars: Bool
    let preferredContentHeight: CGFloat?
    let onRefresh: () -> Void
    let onRequestAccess: () -> Void

    @State private var calendarMonth = Date()
    @State private var monthBirthdays: [CalendarEventSummary] = []

    private static let defaultScrollHeight: CGFloat = 390

    init(
        events: [CalendarEventSummary],
        isSyncing: Bool,
        accessState: CalendarAccessState,
        hasBirthdayCalendars: Bool,
        preferredContentHeight: CGFloat? = nil,
        onRefresh: @escaping () -> Void,
        onRequestAccess: @escaping () -> Void
    ) {
        self.events = events
        self.isSyncing = isSyncing
        self.accessState = accessState
        self.hasBirthdayCalendars = hasBirthdayCalendars
        self.preferredContentHeight = preferredContentHeight
        self.onRefresh = onRefresh
        self.onRequestAccess = onRequestAccess
    }

    private var scrollHeight: CGFloat {
        preferredContentHeight ?? Self.defaultScrollHeight
    }

    private var scheduleEvents: [CalendarEventSummary] {
        events.filter { !$0.isBirthday }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if accessState != .authorized {
                accessPrompt
                    .frame(maxHeight: preferredContentHeight == nil ? nil : .infinity, alignment: .topLeading)
            } else if events.isEmpty && !hasBirthdayCalendars {
                emptyState
                    .frame(maxHeight: preferredContentHeight == nil ? nil : .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if hasBirthdayCalendars {
                            DashboardMonthCalendarView(
                                month: calendarMonth,
                                birthdays: monthBirthdays,
                                scheduledEvents: scheduleEvents,
                                onPreviousMonth: { shiftMonth(by: -1) },
                                onNextMonth: { shiftMonth(by: 1) }
                            )
                        }

                        if !scheduleEvents.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(scheduleEvents) { event in
                                    eventRow(event)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if hasBirthdayCalendars {
                            Text("No other upcoming events in the next two weeks.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
                .frame(height: scrollHeight)
            }

            if isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing schedule…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            reloadMonthBirthdays()
        }
        .onChange(of: calendarMonth) { _, _ in
            reloadMonthBirthdays()
        }
        .onChange(of: hasBirthdayCalendars) { _, _ in
            reloadMonthBirthdays()
        }
        .onChange(of: accessState) { _, _ in
            reloadMonthBirthdays()
        }
        .onChange(of: isSyncing) { _, syncing in
            if !syncing {
                reloadMonthBirthdays()
            }
        }
    }

    private func shiftMonth(by value: Int) {
        calendarMonth = Calendar.current.date(byAdding: .month, value: value, to: calendarMonth) ?? calendarMonth
    }

    private func reloadMonthBirthdays() {
        guard accessState == .authorized, hasBirthdayCalendars else {
            monthBirthdays = []
            return
        }
        monthBirthdays = EventKitCalendarClient.fetchBirthdayEvents(inMonth: calendarMonth)
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow Calendar access to show events from the macOS Calendar app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Allow Calendar Access") {
                onRequestAccess()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No upcoming events in the next two weeks.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Refresh") {
                onRefresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarEventSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeLabel(for: event.startDate))
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text(dayLabel(for: event.startDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if !event.accountEmail.isEmpty {
                    Text(event.accountEmail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !event.location.isEmpty, event.meetingLink == nil {
                    Text(event.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let link = event.meetingLink, let url = URL(string: link) {
                    Button("Join video call") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func timeLabel(for date: Date) -> String {
        DashboardCalendarSchedulePanel.timeFormatter.string(from: date)
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        return DashboardCalendarSchedulePanel.dayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()
}
