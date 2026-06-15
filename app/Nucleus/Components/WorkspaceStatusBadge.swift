import SwiftUI

struct WorkspaceStatusBadge: View {
    let message: String
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: unreadCount > 0 ? "envelope.badge.fill" : "envelope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(unreadCount > 0 ? .blue : .secondary)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.10), in: Capsule())
        .foregroundStyle(.secondary)
    }
}
