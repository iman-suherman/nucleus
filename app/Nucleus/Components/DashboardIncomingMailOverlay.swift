import NucleusKit
import SwiftUI

struct DashboardIncomingMailPrompt: Identifiable, Equatable {
    let id: UUID
    var primaryAccountID: UUID
    var accountName: String
    var newCount: Int
    var totalUnreadCount: Int
    var previewMessages: [MailMessageSummary]

    static func merged(
        existing: DashboardIncomingMailPrompt?,
        accountID: UUID,
        accountName: String,
        delta: Int,
        totalUnread: Int,
        messages: [MailMessageSummary]
    ) -> DashboardIncomingMailPrompt {
        guard delta > 0 else {
            return existing ?? DashboardIncomingMailPrompt(
                primaryAccountID: accountID,
                accountName: accountName,
                newCount: 0,
                totalUnreadCount: totalUnread,
                previewMessages: []
            )
        }

        let combinedMessages = (messages + (existing?.previewMessages ?? []))
            .reduce(into: [String: MailMessageSummary]()) { partial, message in
                partial[message.id] = message
            }
            .values
            .sorted { $0.receivedAt > $1.receivedAt }

        if let existing {
            return DashboardIncomingMailPrompt(
                id: existing.id,
                primaryAccountID: messages.first?.accountID ?? existing.primaryAccountID,
                accountName: messages.isEmpty ? existing.accountName : accountName,
                newCount: existing.newCount + delta,
                totalUnreadCount: totalUnread,
                previewMessages: Array(combinedMessages.prefix(3))
            )
        }

        return DashboardIncomingMailPrompt(
            primaryAccountID: accountID,
            accountName: accountName,
            newCount: delta,
            totalUnreadCount: totalUnread,
            previewMessages: Array(combinedMessages.prefix(3))
        )
    }

    init(
        id: UUID = UUID(),
        primaryAccountID: UUID,
        accountName: String,
        newCount: Int,
        totalUnreadCount: Int,
        previewMessages: [MailMessageSummary]
    ) {
        self.id = id
        self.primaryAccountID = primaryAccountID
        self.accountName = accountName
        self.newCount = newCount
        self.totalUnreadCount = totalUnreadCount
        self.previewMessages = previewMessages
    }

    var headline: String {
        "New email"
    }

    var unreadSummary: String {
        "There's an unread message in your inbox."
    }
}

struct DashboardIncomingMailOverlay: View {
    let prompt: DashboardIncomingMailPrompt
    let onOpenInbox: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.multicolor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.headline)
                            .font(.title3.weight(.semibold))
                        Text(prompt.unreadSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !prompt.accountName.isEmpty {
                            Text(prompt.accountName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
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

                if let preview = prompt.previewMessages.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preview.fromName.isEmpty ? preview.fromEmail : preview.fromName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(preview.subject)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if !preview.snippet.isEmpty, preview.snippet != preview.subject {
                            Text(preview.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 10) {
                    Button(action: onOpenInbox) {
                        Label("Open inbox", systemImage: "envelope.open.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .pointerCursor()

                    Button("Close", action: onDismiss)
                        .buttonStyle(.bordered)
                        .pointerCursor()
                }
            }
            .padding(22)
            .frame(width: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(0.45), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
            .pointerCursor()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(120)
    }
}
