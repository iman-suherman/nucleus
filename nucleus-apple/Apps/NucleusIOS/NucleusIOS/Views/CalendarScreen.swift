import NucleusCore
import NucleusUI
import SwiftUI

struct CalendarWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var selectedAccountEmail: String?

    private var filteredEvents: [CalendarEventSummary] {
        viewModel.filteredCalendarEvents(accountEmail: selectedAccountEmail)
    }

    private var upcomingBirthdays: [CalendarEventSummary] {
        MobileDashboardCalendarHelpers.upcomingBirthdays(in: filteredEvents)
    }

    private var upcomingMeetings: [CalendarEventSummary] {
        MobileDashboardCalendarHelpers.upcomingScheduleEvents(in: filteredEvents)
    }

    var body: some View {
        NavigationStack {
            CalendarDashboardView(
                birthdays: upcomingBirthdays,
                events: upcomingMeetings,
                isSyncing: viewModel.isReloadingCalendar,
                onRefresh: {
                    Task { await viewModel.refreshICloudSync() }
                }
            )
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MobileWorkspaceSettingsButton {
                        viewModel.openSettings()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    calendarMenu
                }
            }
            .safeAreaInset(edge: .bottom) {
                CalendarSyncFooter(syncService: viewModel.iCloudSync)
            }
        }
    }

    private var calendarMenu: some View {
        Menu {
            if !viewModel.calendarAccountEmails.isEmpty {
                Section("Account") {
                    Button {
                        selectedAccountEmail = nil
                    } label: {
                        if selectedAccountEmail == nil {
                            Label("All accounts", systemImage: "checkmark")
                        } else {
                            Text("All accounts")
                        }
                    }

                    ForEach(viewModel.calendarAccountEmails, id: \.self) { email in
                        Button {
                            selectedAccountEmail = email
                        } label: {
                            if selectedAccountEmail == email {
                                Label(email, systemImage: "checkmark")
                            } else {
                                Text(email)
                            }
                        }
                    }
                }
            }

            Button {
                Task { await viewModel.refreshICloudSync() }
            } label: {
                Label("Refresh sync", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "line.3.horizontal.circle")
        }
        .accessibilityLabel("Calendar menu")
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
