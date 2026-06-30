import NucleusCore
import NucleusUI
import SwiftUI

struct CalendarWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel

    private var upcomingEvents: [CalendarEventSummary] {
        viewModel.calendarEvents.filter { $0.endDate >= Date() }
    }

    var body: some View {
        NavigationStack {
            Group {
                if upcomingEvents.isEmpty {
                    ContentUnavailableView {
                        Label("No upcoming events", systemImage: "calendar")
                    } description: {
                        emptyDescription
                    } actions: {
                        Button("Refresh sync") {
                            Task { await viewModel.refreshICloudSync() }
                        }
                    }
                } else {
                    CalendarDashboardView(
                        events: upcomingEvents,
                        isSyncing: viewModel.isReloadingCalendar,
                        onRefresh: {
                            Task { await viewModel.refreshICloudSync() }
                        }
                    )
                }
            }
            .navigationTitle("Calendar")
            .safeAreaInset(edge: .bottom) {
                CalendarSyncFooter(syncService: viewModel.iCloudSync)
            }
            .refreshable {
                await viewModel.refreshICloudSync()
            }
        }
    }

    private var emptyDescription: Text {
        if viewModel.iCloudSync.isSignedIn {
            return Text("Your schedule syncs from Nucleus on your Mac via iCloud. Pull down to refresh.")
        }
        return Text("Sign in to iCloud in Settings to sync your calendar from your Mac.")
    }
}

private struct CalendarSyncFooter: View {
    @ObservedObject var syncService: ICloudSyncDisplayService

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: syncService.isSignedIn ? "icloud.fill" : "icloud.slash")
                .foregroundStyle(syncService.isSignedIn ? Color.accentColor : .secondary)
            Text(syncService.statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
