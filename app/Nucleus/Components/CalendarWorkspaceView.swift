import AppKit
import CalendarKit
import NucleusKit
import SwiftUI

struct CalendarWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var calendarService = MacCalendarSyncService.shared

    private var upcomingEvents: [CalendarEventSummary] {
        viewModel.calendarEvents.filter { $0.endDate >= Date() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            Group {
                if calendarService.accessState != .authorized {
                    accessRequired
                } else if upcomingEvents.isEmpty {
                    emptySchedule
                } else {
                    eventList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            calendarService.refreshAccessState()
            if calendarService.accessState == .authorized {
                Task { await calendarService.syncIfAuthorized() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar")
                    .font(.title2.bold())
                Text("Upcoming events from your macOS Calendar app, synced to iPhone and iPad via iCloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if calendarService.isSyncing {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Refresh") {
                Task { await calendarService.syncIfAuthorized() }
            }
            .buttonStyle(.bordered)
            .disabled(calendarService.isSyncing || calendarService.accessState != .authorized)
        }
    }

    private var accessRequired: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CalendarAccessSetupView()
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var emptySchedule: some View {
        ContentUnavailableView {
            Label("No upcoming events", systemImage: "calendar")
        } description: {
            Text("Nucleus shows events from the next two weeks once Calendar access is enabled.")
        } actions: {
            Button("Refresh") {
                Task { await calendarService.syncIfAuthorized() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedEvents, id: \.day) { group in
                    Text(group.dayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    ForEach(group.events) { event in
                        CalendarWorkspaceEventRow(event: event)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                        Divider()
                            .padding(.leading, 24)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var groupedEvents: [(day: Date, dayLabel: String, events: [CalendarEventSummary])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: upcomingEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
        return grouped.keys.sorted().map { day in
            let events = grouped[day]?.sorted { $0.startDate < $1.startDate } ?? []
            return (day, dayLabel(for: day), events)
        }
    }

    private func dayLabel(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return CalendarWorkspaceView.dayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter
    }()
}

private struct CalendarWorkspaceEventRow: View {
    let event: CalendarEventSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(CalendarWorkspaceEventRow.timeFormatter.string(from: event.startDate))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(CalendarWorkspaceEventRow.timeFormatter.string(from: event.endDate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)

                if !event.accountEmail.isEmpty {
                    Text(event.accountEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !event.location.isEmpty, event.meetingLink == nil {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let link = event.meetingLink, let url = URL(string: link) {
                    Button("Join video call") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
