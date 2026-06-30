import CalendarKit
import NucleusKit
import SwiftUI

/// Rotating next-meeting line for the Nucleus sidebar title. Cycles through overlapping meetings at the same start time.
struct NextMeetingTitleView: View {
    let group: MeetingReminderPlanner.UpcomingMeetingGroup
    let onSelect: (CalendarEventSummary) -> Void

    @State private var rotationIndex = 0
    private let rotationInterval: TimeInterval = 5

    private var events: [CalendarEventSummary] {
        group.events
    }

    private var currentEvent: CalendarEventSummary {
        events[min(rotationIndex, events.count - 1)]
    }

    var body: some View {
        Button {
            onSelect(currentEvent)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !currentEvent.accountEmail.isEmpty {
                    Text(currentEvent.accountEmail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(helpText)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            rotationIndex = 0
            startRotationIfNeeded()
        }
        .onChange(of: group.startDate) { _, _ in
            rotationIndex = 0
        }
        .onChange(of: events.map(\.id)) { _, _ in
            rotationIndex = 0
        }
        .onReceive(Timer.publish(every: rotationInterval, on: .main, in: .common).autoconnect()) { _ in
            guard events.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                rotationIndex = (rotationIndex + 1) % events.count
            }
        }
    }

    private var titleLine: String {
        let time = AppViewModel.nextMeetingTimeLabel(for: group.startDate)
        if events.count > 1 {
            return "\(time) · \(currentEvent.title) (\(rotationIndex + 1)/\(events.count))"
        }
        return "\(time) · \(currentEvent.title)"
    }

    private var helpText: String {
        if events.count > 1 {
            return "Next meetings at \(AppViewModel.nextMeetingTimeLabel(for: group.startDate)). Click to open calendar — rotates through \(events.count) overlapping invites."
        }
        return "Next meeting at \(AppViewModel.nextMeetingTimeLabel(for: group.startDate)). Click to open calendar."
    }

    private var accessibilityText: String {
        let email = currentEvent.accountEmail.isEmpty ? "" : ", \(currentEvent.accountEmail)"
        return "Next meeting \(titleLine)\(email). Open in calendar."
    }

    private func startRotationIfNeeded() {
        rotationIndex = min(rotationIndex, max(events.count - 1, 0))
    }
}
