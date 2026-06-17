import NucleusCore
import NucleusUI
import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel

    var body: some View {
        TabView(selection: tabBinding) {
            ForEach(MobileWorkspaceTab.iosTabs) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: MobileWorkspaceTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardWorkspaceScreen()
        case .notes:
            NotesWorkspaceScreen()
        case .passwords:
            PasswordsWorkspaceScreen()
        case .bills:
            BillsWorkspaceScreen()
        case .settings:
            SettingsWorkspaceScreen()
        default:
            DashboardWorkspaceScreen()
        }
    }

    private var tabBinding: Binding<MobileWorkspaceTab> {
        Binding(
            get: { viewModel.selectedTab },
            set: { viewModel.selectedTab = $0 }
        )
    }
}
