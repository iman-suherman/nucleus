import NucleusCore
import NucleusUI
import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel

    var body: some View {
        TabView(selection: tabBinding) {
            NotesWorkspaceScreen()
                .tabItem { Label(MobileWorkspaceTab.notes.title, systemImage: MobileWorkspaceTab.notes.icon) }
                .tag(MobileWorkspaceTab.notes)

            SettingsWorkspaceScreen()
                .tabItem { Label(MobileWorkspaceTab.settings.title, systemImage: MobileWorkspaceTab.settings.icon) }
                .tag(MobileWorkspaceTab.settings)
        }
    }

    private var tabBinding: Binding<MobileWorkspaceTab> {
        Binding(
            get: { viewModel.selectedTab },
            set: { viewModel.selectedTab = $0 }
        )
    }
}
