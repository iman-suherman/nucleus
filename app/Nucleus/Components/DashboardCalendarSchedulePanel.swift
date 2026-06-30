import AppKit
import CalendarKit
import NucleusKit
import SwiftUI

struct DashboardCalendarSchedulePanel: View {
    let events: [CalendarEventSummary]
    let isSyncing: Bool
    let accessState: CalendarAccessState
    let preferredContentHeight: CGFloat?
    let onRefresh: () -> Void
    let onRequestAccess: () -> Void

    private static let defaultScrollHeight: CGFloat = 390

    init(
        events: [CalendarEventSummary],
        isSyncing: Bool,
        accessState: CalendarAccessState,
        preferredContentHeight: CGFloat? = nil,
        onRefresh: @escaping () -> Void,
        onRequestAccess: @escaping () -> Void
    ) {
        self.events = events
        self.isSyncing = isSyncing
        self.accessState = accessState
        self.preferredContentHeight = preferredContentHeight
        self.onRefresh = onRefresh
        self.onRequestAccess = onRequestAccess
    }

    private var scrollHeight: CGFloat {
        preferredContentHeight ?? Self.defaultScrollHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if accessState != .authorized {
                accessPrompt
                    .frame(maxHeight: preferredContentHeight == nil ? nil : .infinity, alignment: .topLeading)
            } else if events.isEmpty {
                emptyState
                    .frame(maxHeight: preferredContentHeight == nil ? nil : .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
