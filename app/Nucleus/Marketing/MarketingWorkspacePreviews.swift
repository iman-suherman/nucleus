import NucleusKit
import SwiftUI

struct MarketingWorkspacePreview: View {
    let pane: WorkspacePane

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .dashboard:
            dashboardPreview
        case .inbox:
            inboxPreview
        case .clipboard:
            clipboardPreview
        case .notes:
            notesPreview
        case .bills:
            billsPreview
        case .media:
            musicPreview
        case .terminal:
            terminalPreview
        default:
            EmptyView()
        }
    }

    private var dashboardPreview: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Good morning, Alex.")
                    .font(.title.weight(.semibold))
                Text("Saturday, 27 June 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Focus beats friction — start with one clear win.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            marketingCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Intelligent insight")
                        .font(.headline)
                    Text("You have 3 unread messages, 2 bills due soon, and a healthy clipboard rhythm today. Notes and passwords look current.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                statTile(title: "Unread email", value: "3", tint: .blue)
                statTile(title: "Passwords", value: "8", tint: .orange)
                statTile(title: "Bills due", value: "2", tint: .green)
            }

            marketingCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your day")
                        .font(.headline)
                    Text("Clipboard captures lean toward development and notes — consolidate draft snippets before your next meeting.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var inboxPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                accountTab("Personal", selected: true)
                accountTab("Work")
                accountTab("Client")
            }

            VStack(spacing: 0) {
                inboxRow(sender: "Product Team", subject: "Sprint review notes for Monday", time: "9:14 AM", unread: true)
                Divider()
                inboxRow(sender: "Billing", subject: "Invoice ready for March services", time: "8:02 AM", unread: true)
                Divider()
                inboxRow(sender: "Newsletter", subject: "Weekly digest — tools for focused work", time: "Yesterday", unread: false)
                Divider()
                inboxRow(sender: "Calendar", subject: "Updated invite: Design sync", time: "Yesterday", unread: false)
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var clipboardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search clipboard history", text: .constant(""))
                .textFieldStyle(.roundedBorder)

            ForEach(clipboardSamples, id: \.self) { sample in
                marketingCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sample)
                            .font(.body.monospaced())
                            .lineLimit(2)
                        Text("Cursor · 2 minutes ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var notesPreview: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Folders")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                folderRow("Notes", count: 2, tint: .blue, selected: true)
                folderRow("Passwords", count: 3, tint: .orange)
            }
            .frame(width: 180, alignment: .leading)

            marketingCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Weekly planning")
                        .font(.headline)
                    Text("# Priorities\n\n- Ship marketing screenshots\n- Review bill payments\n- Capture meeting notes")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var billsPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                statTile(title: "Due soon", value: "$248", tint: .orange)
                statTile(title: "Paid", value: "$1,120", tint: .green)
            }

            ForEach(billSamples, id: \.name) { bill in
                marketingCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bill.name)
                                .font(.headline)
                            Text("Due \(bill.due) · \(bill.category)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(bill.amount)
                            .font(.headline.monospaced())
                    }
                }
            }
        }
    }

    private var musicPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Search Apple Music", text: .constant("focus playlist"))
                .textFieldStyle(.roundedBorder)

            marketingCard {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deep Work Flow")
                            .font(.headline)
                        Text("Focus Studio · Apple Music catalog")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.accentColor)
                }
            }

            marketingCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Synced lyrics")
                        .font(.headline)
                    Text("Stay in rhythm, stay in flow\nKeep your mind clear, take it slow")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var terminalPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Active tmux sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Drag cards to reorder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(terminalSamples, id: \.name) { session in
                marketingCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "terminal.fill")
                                .foregroundStyle(.secondary)
                            Text(session.name)
                                .font(.subheadline.monospaced().weight(.semibold))
                            Spacer()
                            Text(session.meta)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("env -u TMUX tmux attach -t \(session.name)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Label("Attach", systemImage: "arrow.right.circle")
                                .font(.caption)
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func marketingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private func statTile(title: String, value: String, tint: Color) -> some View {
        marketingCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
    }

    private func accountTab(_ title: String, selected: Bool = false) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                in: Capsule()
            )
    }

    private func inboxRow(sender: String, subject: String, time: String, unread: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(unread ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(sender)
                        .font(.subheadline.weight(unread ? .semibold : .regular))
                    Spacer()
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(subject)
                    .font(.subheadline)
                    .foregroundStyle(unread ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func folderRow(_ title: String, count: Int, tint: Color, selected: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(.white)
                .background(tint.opacity(0.85), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var clipboardSamples: [String] {
        [
            "npm run dev",
            "Meeting notes — Q2 planning priorities",
            "https://docs.example.com/handbook",
        ]
    }

    private var billSamples: [(name: String, due: String, category: String, amount: String)] {
        [
            ("Cloud Storage", "in 3 days", "Subscriptions", "$24.00"),
            ("Mobile Plan", "in 8 days", "Utilities", "$65.00"),
            ("Music Streaming", "in 12 days", "Subscriptions", "$16.99"),
        ]
    }

    private var terminalSamples: [(name: String, meta: String)] {
        [
            ("nucleus-dev", "2w · attached"),
            ("nucleus-ci", "1w"),
        ]
    }
}
