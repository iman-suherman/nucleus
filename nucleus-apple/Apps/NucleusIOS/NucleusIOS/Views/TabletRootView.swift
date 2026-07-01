import NucleusCore
import NucleusUI
import SwiftUI

struct TabletRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var selection: MobileWorkspaceTab = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                ForEach(MobileWorkspaceTab.iosMainTabs) { tab in
                    SidebarRow(
                        tab: tab,
                        badgeCount: viewModel.tabBadgeCount(for: tab),
                        isSelected: selection == tab
                    ) {
                        selection = tab
                    }
                }

                Section {
                    Button {
                        viewModel.openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("mobile.settings.sidebar")
                }
            }
            .navigationTitle("Nucleus")
        } detail: {
            detailView(for: selection)
                .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: selection) { _, newValue in
            viewModel.selectedTab = newValue
        }
        .onChange(of: viewModel.selectedTab) { _, newValue in
            selection = newValue
        }
        .onAppear {
            selection = MobileWorkspaceTab.normalizedForIOS(viewModel.selectedTab)
        }
    }

    @ViewBuilder
    private func detailView(for tab: MobileWorkspaceTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardWorkspaceScreen()
        case .notes:
            NotesWorkspaceScreen()
        case .passwords:
            PasswordsWorkspaceScreen()
        case .bills:
            BillsWorkspaceScreen()
        case .calendar:
            CalendarWorkspaceScreen()
        default:
            DashboardWorkspaceScreen()
        }
    }
}

private struct SidebarRow: View {
    let tab: MobileWorkspaceTab
    let badgeCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(tab.title, systemImage: tab.icon)
                Spacer(minLength: 0)
                if badgeCount > 0 {
                    MobileCountBadge(count: badgeCount, kind: .warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
    }
}
