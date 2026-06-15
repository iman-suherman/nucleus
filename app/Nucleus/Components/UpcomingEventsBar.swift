import NucleusKit
import SwiftUI

struct UpcomingEventsBar: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var events: [CalendarEventSummary] {
        viewModel.upcomingEvents(limit: 8)
    }

    var body: some View {
        if !events.isEmpty {
            VStack(spacing: 0) {
                Divider().overlay(NucleusTheme.divider)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            UpcomingEventChip(
                                event: event,
                                accountName: viewModel.accountDisplayName(for: event.accountID),
                                isNext: index == 0,
                                onSelect: { viewModel.openCalendar(for: event) },
                                onJoin: joinMeeting
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(NucleusTheme.canvas)
                Divider().overlay(NucleusTheme.divider)
            }
        }
    }

    private func joinMeeting(_ event: CalendarEventSummary) {
        guard let link = event.meetingLink, let url = URL(string: link) else { return }
        ChromeLauncher.open(url: url)
    }
}

private struct UpcomingEventChip: View {
    let event: CalendarEventSummary
    let accountName: String
    let isNext: Bool
    let onSelect: () -> Void
    let onJoin: (CalendarEventSummary) -> Void

    private var isInProgress: Bool {
        let now = Date()
        return event.startDate <= now && event.endDate > now
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isNext {
                            Text(isInProgress ? "Now" : "Next")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.18), in: Capsule())
                        }

                        Text(timingLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(accountName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if event.meetingLink != nil {
                    Button("Join") {
                        onJoin(event)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isNext ? NucleusTheme.selected.opacity(0.85) : NucleusTheme.surface,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    private var timingLabel: String {
        if isInProgress {
            return "In progress · ends \(NucleusFormatters.time.string(from: event.endDate))"
        }
        if Calendar.current.isDateInToday(event.startDate) {
            return "Today \(NucleusFormatters.time.string(from: event.startDate))"
        }
        if Calendar.current.isDateInTomorrow(event.startDate) {
            return "Tomorrow \(NucleusFormatters.time.string(from: event.startDate))"
        }
        return "\(NucleusFormatters.dayHeader.string(from: event.startDate)) · \(NucleusFormatters.time.string(from: event.startDate))"
    }
}
