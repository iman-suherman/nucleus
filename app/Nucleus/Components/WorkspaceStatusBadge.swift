import SwiftUI

struct UnreadAccountBreakdown: Identifiable {
    let id: UUID
    let name: String
    let count: Int
}

struct WorkspaceStatusBadge: View {
    let message: String
    let mailUnreadCount: Int
    let mailAccounts: [UnreadAccountBreakdown]

    private var hasUnread: Bool {
        mailUnreadCount > 0
    }

    private var statusLine: String {
        if hasUnread {
            return unreadSummaryMessage
        }
        return message
    }

    private var unreadSummaryMessage: String {
        guard mailUnreadCount > 0 else { return message }
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

    var body: some View {
        HStack(spacing: 10) {
            if hasUnread {
                unreadPill(count: mailUnreadCount, icon: "envelope.fill", tint: .blue)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Text(statusLine)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .help(hasUnread ? unreadDetailMessage : message)
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
