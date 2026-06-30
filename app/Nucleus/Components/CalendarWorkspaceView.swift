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

    private var selectedEvent: CalendarEventSummary? {
        guard let id = viewModel.selectedCalendarEventID else { return nil }
        return upcomingEvents.first { $0.id == id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
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
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            CalendarEventDetailPanel(event: selectedEvent)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            calendarService.refreshAccessState()
            if calendarService.accessState == .authorized {
                Task { await calendarService.syncIfAuthorized() }
            }
            selectDefaultEventIfNeeded()
        }
        .onChange(of: viewModel.selectedCalendarEventID) { _, _ in
            scrollToSelectionTrigger.toggle()
        }
        .onChange(of: upcomingEvents.map(\.id)) { _, _ in
            selectDefaultEventIfNeeded()
        }
    }

    @State private var scrollToSelectionTrigger = false

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
        ScrollViewReader { proxy in
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
                            CalendarWorkspaceEventRow(
                                event: event,
                                isSelected: viewModel.selectedCalendarEventID == event.id
                            )
                            .id(event.id)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedCalendarEventID = event.id
                            }
                            Divider()
                                .padding(.leading, 24)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .onAppear {
                scrollToSelectedEvent(using: proxy)
            }
            .onChange(of: scrollToSelectionTrigger) { _, _ in
                scrollToSelectedEvent(using: proxy)
            }
        }
    }

    private func scrollToSelectedEvent(using proxy: ScrollViewProxy) {
        guard let id = viewModel.selectedCalendarEventID else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func selectDefaultEventIfNeeded() {
        guard let id = viewModel.selectedCalendarEventID,
              upcomingEvents.contains(where: { $0.id == id }) else {
            if viewModel.selectedCalendarEventID == nil,
               let next = upcomingEvents.filter({ $0.startDate > Date() }).sorted(by: { $0.startDate < $1.startDate }).first {
                viewModel.selectedCalendarEventID = next.id
            }
            return
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
    let isSelected: Bool

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
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.purple.opacity(0.16) : Color.clear)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.45), lineWidth: 1.5)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct CalendarEventDetailPanel: View {
    let event: CalendarEventSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let event {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        detailHeader(event)

                        if !event.accountEmail.isEmpty {
                            detailSection(title: "Calendar", icon: "envelope.fill") {
                                Text(event.accountEmail)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }

                        detailSection(title: "When", icon: "clock") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CalendarEventDetailPanel.dateFormatter.string(from: event.startDate))
                                Text("\(CalendarEventDetailPanel.timeFormatter.string(from: event.startDate)) – \(CalendarEventDetailPanel.timeFormatter.string(from: event.endDate))")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }

                        if !event.location.isEmpty {
                            detailSection(title: "Location", icon: "mappin.and.ellipse") {
                                Text(event.location)
                                    .font(.subheadline)
                            }
                        }

                        if !event.attendees.isEmpty {
                            detailSection(title: "Attendees", icon: "person.2") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(event.attendees, id: \.self) { attendee in
                                        Text(attendee)
                                            .font(.caption)
                                    }
                                }
                            }
                        }

                        if let link = event.meetingLink, let url = URL(string: link) {
                            detailSection(title: "Video call", icon: "video.fill") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(link)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .lineLimit(2)
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label("Join meeting", systemImage: "video.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView {
                    Label("No event selected", systemImage: "calendar")
                } description: {
                    Text("Choose an event from the schedule or click the next meeting in the Nucleus title.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func detailHeader(_ event: CalendarEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(AppViewModel.nextMeetingTimeLabel(for: event.startDate))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMMM d, yyyy")
        return formatter
    }()
}
