import NucleusKit
import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity Feed")
                    .font(.title2.bold())
                Text("Gmail, calendar, clipboard, and notes in one stream.")
                    .foregroundStyle(.secondary)

                if viewModel.activityFeed.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "bell",
                        description: Text("Notifications from all workspaces will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(viewModel.activityFeed) { item in
                        ActivityRow(item: item)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(NucleusFormatters.time.string(from: item.timestamp))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let email = item.accountEmail {
                        Text(email)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private var iconName: String {
        switch item.source {
        case .gmail: return "envelope"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        }
    }
}
