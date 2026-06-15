import SwiftUI

struct UnreadAccountBreakdown: Identifiable {
    let id: UUID
    let name: String
    let count: Int
}

struct WorkspaceStatusBadge: View {
    let message: String
    let mailUnreadCount: Int
    let chatUnreadCount: Int
    let mailAccounts: [UnreadAccountBreakdown]
    let chatAccounts: [UnreadAccountBreakdown]

    private let chatBadgeColor = Color(red: 129 / 255, green: 201 / 255, blue: 149 / 255)

    private var hasUnread: Bool {
        mailUnreadCount > 0 || chatUnreadCount > 0
    }

    private var showsOperationalMessage: Bool {
        hasUnread && message != unreadSummaryMessage
    }

    private var unreadSummaryMessage: String {
        var parts: [String] = []
        if mailUnreadCount > 0 {
            parts.append("\(mailUnreadCount) unread email\(mailUnreadCount == 1 ? "" : "s")")
        }
        if chatUnreadCount > 0 {
            parts.append("\(chatUnreadCount) unread chat\(chatUnreadCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private var unreadDetailMessage: String {
        var accountParts: [String] = []
        for account in mailAccounts where account.count > 0 {
            accountParts.append("\(account.name) \(account.count) mail")
        }
        for account in chatAccounts where account.count > 0 {
            accountParts.append("\(account.name) \(account.count) chat")
        }

        guard !accountParts.isEmpty else { return unreadSummaryMessage }
        return "\(unreadSummaryMessage) — \(accountParts.joined(separator: ", "))"
    }

    var body: some View {
        HStack(spacing: 12) {
            if hasUnread {
                HStack(spacing: 6) {
                    if mailUnreadCount > 0 {
                        unreadPill(count: mailUnreadCount, icon: "envelope.fill", tint: .blue)
                    }
                    if chatUnreadCount > 0 {
                        unreadPill(count: chatUnreadCount, icon: "message.fill", tint: chatBadgeColor)
                    }
                }

                Divider()
                    .frame(height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(unreadDetailMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsOperationalMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minWidth: 360, idealWidth: 480, maxWidth: 560)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func unreadPill(count: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text("\(count)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.18), in: Capsule())
    }
}
