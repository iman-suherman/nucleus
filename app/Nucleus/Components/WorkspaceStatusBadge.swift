import SwiftUI

struct WorkspaceStatusBadge: View {
    let message: String
    let mailUnreadCount: Int
    let chatUnreadCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if mailUnreadCount > 0 || chatUnreadCount > 0 {
                HStack(spacing: 6) {
                    if mailUnreadCount > 0 {
                        unreadPill(
                            count: mailUnreadCount,
                            icon: "envelope.fill",
                            tint: NucleusTheme.mailBadge
                        )
                    }
                    if chatUnreadCount > 0 {
                        unreadPill(
                            count: chatUnreadCount,
                            icon: "message.fill",
                            tint: NucleusTheme.chatBadge
                        )
                    }
                }
            } else {
                Image(systemName: "envelope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NucleusTheme.textSecondary)
            }

            Text(message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(NucleusTheme.textPrimary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(NucleusTheme.surface, in: Capsule())
    }

    private func unreadPill(count: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text("\(count)")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.18), in: Capsule())
    }
}
