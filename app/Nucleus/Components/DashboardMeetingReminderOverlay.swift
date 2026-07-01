import CalendarKit
import NucleusKit
import SwiftUI

struct DashboardMeetingReminderPrompt: Identifiable, Equatable {
    let events: [CalendarEventSummary]
    let kind: MeetingReminderPlanner.Reminder.Kind
    let startDate: Date

    var id: String {
        events.map(\.id).sorted().joined(separator: "|")
    }

    var headline: String {
        if events.count > 1 {
            return "\(events.count) meetings \(CalendarEventFormatting.timeUntilStartLabel(for: startDate))"
        }
        return CalendarEventFormatting.meetingStartsInLabel(for: startDate)
    }

    var startLabel: String {
        DashboardMeetingReminderOverlay.timeFormatter.string(from: startDate)
    }
}

struct DashboardMeetingReminderOverlay: View {
    let prompt: DashboardMeetingReminderPrompt
    let onJoinMeeting: (CalendarEventSummary) -> Void
    let onOpenCalendar: () -> Void
    let onDismiss: () -> Void

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                if prompt.events.count == 1, let event = prompt.events.first {
                    singleMeetingDetail(event)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(prompt.events) { event in
                                meetingChoiceRow(event)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }

                footerButtons
            }
            .padding(22)
            .frame(width: prompt.events.count > 1 ? 460 : 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.45), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
            .pointerCursor()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(130)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: prompt.events.count > 1 ? "video.badge.waveform.fill" : "video.fill")
                .font(.system(size: 28))
                .foregroundStyle(.purple)
                .symbolRenderingMode(.multicolor)

            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.headline)
                    .font(.title3.weight(.semibold))
                Text("Starts at \(prompt.startLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if prompt.events.count > 1 {
                    Text("Choose the invite for the account you want to join.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .pointerCursor()
        }
    }

    @ViewBuilder
    private func singleMeetingDetail(_ event: CalendarEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            inviteOriginBadge(for: event)

            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if let link = event.meetingLink, !link.isEmpty {
                Text(link)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            } else if !event.location.isEmpty {
                Text(event.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func meetingChoiceRow(_ event: CalendarEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            inviteOriginBadge(for: event)

            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if let link = event.meetingLink, !link.isEmpty {
                Text(link)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if !event.location.isEmpty {
                Text(event.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if event.meetingLink != nil {
                Button {
                    onJoinMeeting(event)
                } label: {
                    Label("Join this meeting", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointerCursor()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.purple.opacity(0.22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func inviteOriginBadge(for event: CalendarEventSummary) -> some View {
        if !event.accountEmail.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.caption2)
                Text(event.accountEmail)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.orange.opacity(0.45), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        HStack(spacing: 10) {
            if prompt.events.count == 1, let event = prompt.events.first {
                if event.meetingLink != nil {
                    Button {
                        onJoinMeeting(event)
                    } label: {
                        Label("Join meeting", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .pointerCursor()
                } else {
                    Button(action: onOpenCalendar) {
                        Label("Open calendar", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .pointerCursor()
                }
            } else if prompt.events.allSatisfy({ $0.meetingLink == nil }) {
                Button(action: onOpenCalendar) {
                    Label("Open calendar", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .pointerCursor()
            }

            Button("Close", action: onDismiss)
                .buttonStyle(.bordered)
                .pointerCursor()
        }
    }
}
