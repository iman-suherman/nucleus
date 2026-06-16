import NucleusCore
import NucleusUI
import SwiftUI

private enum TabletSection: String, CaseIterable, Identifiable, Hashable {
    case notes
    case settings

    var id: String { rawValue }

    var tab: MobileWorkspaceTab {
        switch self {
        case .notes: return .notes
        case .settings: return .settings
        }
    }

    var title: String { tab.title }
    var icon: String { tab.icon }
}

struct TabletRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var selection: TabletSection = .notes
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                ForEach(TabletSection.allCases) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }
            }
            .navigationTitle("Nucleus")
        } detail: {
            detailView(for: selection)
                .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: selection) { _, newValue in
            viewModel.selectedTab = newValue.tab
        }
        .onAppear {
            let tab = MobileWorkspaceTab.normalizedForIOS(viewModel.selectedTab)
            selection = TabletSection(rawValue: tab.rawValue) ?? .notes
        }
    }

    @ViewBuilder
    private func detailView(for section: TabletSection) -> some View {
        switch section {
        case .notes:
            NotesWorkspaceScreen()
        case .settings:
            SettingsWorkspaceScreen()
        }
    }
}

private struct SidebarRow: View {
    let section: TabletSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
    }
}
