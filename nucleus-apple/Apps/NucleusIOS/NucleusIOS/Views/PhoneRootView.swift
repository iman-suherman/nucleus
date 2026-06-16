import NucleusCore
import NucleusUI
import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel

    var body: some View {
        TabView(selection: tabBinding) {
            MailWorkspaceScreen()
                .tabItem { Label(MobileWorkspaceTab.mail.title, systemImage: MobileWorkspaceTab.mail.icon) }
                .tag(MobileWorkspaceTab.mail)

            CalendarWorkspaceScreen()
                .tabItem { Label(MobileWorkspaceTab.calendar.title, systemImage: MobileWorkspaceTab.calendar.icon) }
                .tag(MobileWorkspaceTab.calendar)

            ChatWorkspaceScreen()
                .tabItem { Label(MobileWorkspaceTab.chat.title, systemImage: MobileWorkspaceTab.chat.icon) }
                .tag(MobileWorkspaceTab.chat)

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
