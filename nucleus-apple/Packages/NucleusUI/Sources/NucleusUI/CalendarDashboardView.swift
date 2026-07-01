import NucleusCore
import SwiftUI

public struct CalendarDashboardView: View {
    let birthdays: [CalendarEventSummary]
    let events: [CalendarEventSummary]
    let isSyncing: Bool
    let onRefresh: () -> Void

    public init(
        birthdays: [CalendarEventSummary],
        events: [CalendarEventSummary],
        isSyncing: Bool,
        onRefresh: @escaping () -> Void
    ) {
        self.birthdays = birthdays
        self.events = events
        self.isSyncing = isSyncing
        self.onRefresh = onRefresh
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing schedule…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if birthdays.isEmpty && events.isEmpty {
                    ContentUnavailableView(
                        "No upcoming events",
                        systemImage: "calendar",
                        description: Text("Pull to refresh after syncing from your Mac.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    CalendarScheduleListView(
                        birthdays: birthdays,
                        events: events
                    )
                }
            }
            .padding()
        }
        .refreshable {
            onRefresh()
        }
    }
}
