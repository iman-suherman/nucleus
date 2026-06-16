import NucleusCore
import NucleusUI
import SwiftUI

private enum TabletSection: String, CaseIterable, Identifiable, Hashable {
    case mail
    case calendar
    case chat
    case notes
    case settings

    var id: String { rawValue }

    var tab: MobileWorkspaceTab {
        switch self {
        case .mail: return .mail
        case .calendar: return .calendar
        case .chat: return .chat
        case .notes: return .notes
        case .settings: return .settings
        }
    }

    var title: String { tab.title }
    var icon: String { tab.icon }
}

struct TabletRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var selection: TabletSection = .mail
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
            .safeAreaInset(edge: .bottom) {
                if !viewModel.accountService.accounts.isEmpty {
                    AccountSidebarFooter()
                        .padding()
                }
            }
        } detail: {
            detailView(for: selection)
                .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: selection) { _, newValue in
            viewModel.selectedTab = newValue.tab
        }
        .onAppear {
            selection = TabletSection(rawValue: viewModel.selectedTab.rawValue) ?? .mail
        }
    }

    @ViewBuilder
    private func detailView(for section: TabletSection) -> some View {
        switch section {
        case .mail:
            MailWorkspaceScreen()
        case .calendar:
            CalendarWorkspaceScreen()
        case .chat:
            ChatWorkspaceScreen()
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

private struct AccountSidebarFooter: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(viewModel.accountService.accounts) { account in
                HStack {
                    Image(systemName: account.isPrimary ? "star.fill" : "person.crop.circle")
                        .foregroundStyle(account.isPrimary ? .yellow : .secondary)
                    Text(account.email)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            Button("Add account") {
                viewModel.showAddAccount = true
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
