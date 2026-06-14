import NucleusKit
import SwiftUI

struct CalendarWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                timeline
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unified Timeline")
                .font(.title2.bold())
            Text("Meetings across Personal, Work, and Client calendars.")
                .foregroundStyle(.secondary)
        }
    }

    private var timeline: some View {
        VStack(spacing: 12) {
            if viewModel.calendarEvents.isEmpty {
                ContentUnavailableView(
                    "No upcoming events",
                    systemImage: "calendar",
                    description: Text("Connect Google accounts to sync your calendars.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ForEach(viewModel.calendarEvents) { event in
                    CalendarEventCard(event: event)
                }
            }
        }
    }
}

private struct CalendarEventCard: View {
    let event: CalendarEventSummary

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NucleusFormatters.time.string(from: event.startDate))
                    .font(.headline.monospacedDigit())
                Text(NucleusFormatters.time.string(from: event.endDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.headline)
                Text(event.accountEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !event.attendees.isEmpty {
                    Text(event.attendees.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let link = event.meetingLink, let url = URL(string: link) {
                    Button("Join Meeting") {
                        ChromeLauncher.open(url: url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}
