import CalendarKit
import NucleusKit
import SwiftUI

struct UnreadAccountBreakdown: Identifiable {
    let id: UUID
    let name: String
    let count: Int
}

struct WorkspaceStatusBadge: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let fallbackMessage: String
    let mailUnreadCount: Int
    let mailAccounts: [UnreadAccountBreakdown]

    private var hasUnread: Bool {
        mailUnreadCount > 0
    }

    private var nextScheduleEvent: CalendarEventSummary? {
        guard !hasUnread else { return nil }
        return viewModel.currentNextMeetingTitleEvent
    }

    private var statusLine: String {
        if hasUnread {
            return unreadSummaryMessage
        }
        if let event = nextScheduleEvent {
            return viewModel.nextScheduleStatusLine(for: event)
        }
        return fallbackMessage
    }

    private var unreadSummaryMessage: String {
        guard mailUnreadCount > 0 else { return fallbackMessage }
        return "\(mailUnreadCount) unread email\(mailUnreadCount == 1 ? "" : "s")"
    }

    private var unreadDetailMessage: String {
        var accountParts: [String] = []
        for account in mailAccounts where account.count > 0 {
            accountParts.append("\(account.name) \(account.count) mail")
        }

        guard !accountParts.isEmpty else { return unreadSummaryMessage }
        return "\(unreadSummaryMessage) — \(accountParts.joined(separator: ", "))"
    }

    private var helpText: String {
        if hasUnread {
            return "\(unreadDetailMessage). Click to open Inbox."
        }
        if let event = nextScheduleEvent {
            let countdown = CalendarEventFormatting.timeUntilStartLabel(for: event.startDate)
            return "Open \(event.title) \(countdown) (\(CalendarEventFormatting.scheduleTimeAndDurationLabel(for: event)))."
        }
        return fallbackMessage
    }

    var body: some View {
        Group {
            if hasUnread {
                Button {
                    viewModel.openInboxFromDashboardUnreadSummary()
                } label: {
                    badgeBody
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help(helpText)
                .accessibilityLabel("\(statusLine). Open Inbox.")
            } else if let event = nextScheduleEvent {
                Button {
                    viewModel.openCalendarEvent(event)
                } label: {
                    badgeBody
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help(helpText)
                .accessibilityLabel("Next schedule: \(statusLine). Open in calendar.")
            } else {
                badgeBody
                    .help(helpText)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.nextMeetingTitleRotationIndex)
    }

    private var badgeBody: some View {
        HStack(spacing: 10) {
            if hasUnread {
                unreadPill(count: mailUnreadCount, icon: "envelope.fill", tint: .blue)
            } else if nextScheduleEvent != nil {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Text(statusLine)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .id(nextScheduleEvent?.id ?? fallbackMessage)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }

    private func unreadPill(count: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text("\(count)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.18), in: Capsule())
    }
}
