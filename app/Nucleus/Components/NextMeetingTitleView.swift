import NucleusKit
import SwiftUI

/// Rotating next-meeting line for the Nucleus sidebar title. Cycles through each upcoming meeting individually.
struct NextMeetingTitleView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        if let event = viewModel.currentNextMeetingTitleEvent {
            Button {
                viewModel.openCalendarEvent(event)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleLine(for: event))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id(event.id)

                    if !event.accountEmail.isEmpty {
                        Text(event.accountEmail)
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
            .help(helpText(for: event))
            .accessibilityLabel(accessibilityText(for: event))
            .animation(.easeInOut(duration: 0.25), value: viewModel.nextMeetingTitleRotationIndex)
        }
    }

    private func titleLine(for event: CalendarEventSummary) -> String {
        let time = AppViewModel.nextMeetingTimeLabel(for: event.startDate)
        return "\(time) · \(event.title)"
    }

    private func helpText(for event: CalendarEventSummary) -> String {
        "Next meeting at \(AppViewModel.nextMeetingTimeLabel(for: event.startDate)). Click to open \(event.title) in calendar."
    }

    private func accessibilityText(for event: CalendarEventSummary) -> String {
        let email = event.accountEmail.isEmpty ? "" : ", \(event.accountEmail)"
        return "Next meeting \(titleLine(for: event))\(email). Open in calendar."
    }
}
