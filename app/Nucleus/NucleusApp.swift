import AppKit
import NucleusKit
import SwiftUI
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icnsURL) {
            NSApp.applicationIconImage = image
        }

        DispatchQueue.main.async {
            _ = SparkleUpdaterController.shared
        }
    }
}

@main
struct NucleusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var appSettings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(appSettings)
                .modelContainer(viewModel.modelContainer)
                .frame(minWidth: 1180, minHeight: 780)
                .task {
                    await viewModel.bootstrap(settings: appSettings)
                }
                .sheet(item: $viewModel.quickReplyContext) { context in
                    QuickReplySheet(context: context)
                        .environmentObject(viewModel)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    viewModel.checkForUpdatesWhenEligible()
                }
        }
        .defaultSize(width: 1320, height: 880)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    SparkleUpdaterController.shared.checkForUpdates()
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    viewModel.sidebarSelection = .workspace(.accounts)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Paste from Clipboard History…") {
                    ClipboardPasteController.shared.presentPicker()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings {
            AppSettingsView(settings: appSettings)
                .frame(width: 520, height: 420)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                UpcomingEventsBar()
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
                } detail: {
                    detailContent
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                WorkspaceStatusBadge(
                                    message: viewModel.statusMessage,
                                    unreadCount: viewModel.totalUnread
                                )
                            }
                            ToolbarItem(placement: .automatic) {
                                Button {
                                    SparkleUpdaterController.shared.checkForUpdates()
                                } label: {
                                    Label("Check for Updates…", systemImage: "arrow.down.circle")
                                        .labelStyle(.titleAndIcon)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                }
            }

            if viewModel.isStartingUp {
                StartupSplashOverlay(
                    version: AppSettings.currentAppVersion,
                    currentMessage: viewModel.startupMessage,
                    completedSteps: viewModel.startupCompletedSteps,
                    activeStep: viewModel.startupActiveStep,
                    progressFraction: viewModel.startupProgressFraction
                )
            }

            ForEach(viewModel.webSessionAccounts) { account in
                ChatUnreadPoller(accountID: account.id, accountEmail: account.email)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.isStartingUp)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.sidebarSelection {
        case .workspace(.inbox):
            MailWorkspaceView()
        case .workspace(.calendar):
            CalendarWorkspaceView()
        case .workspace(.chat):
            ChatWorkspaceView()
        case .workspace(.clipboard):
            ClipboardWorkspaceView()
        case .workspace(.notes):
            NotesWorkspaceView()
        case .workspace(.notifications):
            NotificationCenterView()
        case .workspace(.accounts):
            AccountCenterView()
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.sidebarSelection) {
            Section {
                Text("Nucleus")
                    .font(.title2.bold())
                    .padding(.vertical, 4)
                Text("Personal Operating System")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Workspace") {
                ForEach(WorkspacePane.primaryWorkspaces) { pane in
                    sidebarRow(for: pane)
                        .tag(SidebarSelection.workspace(pane))
                }
            }

            Section("System") {
                ForEach(WorkspacePane.utilityWorkspaces) { pane in
                    sidebarRow(for: pane)
                        .tag(SidebarSelection.workspace(pane))
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(for pane: WorkspacePane) -> some View {
        HStack(spacing: 10) {
            Image(systemName: pane.icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                Text(pane.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            badge(for: pane)
        }
    }

    @ViewBuilder
    private func badge(for pane: WorkspacePane) -> some View {
        switch pane {
        case .inbox where viewModel.totalUnread > 0:
            sidebarCountBadge(viewModel.totalUnread)
        case .chat where viewModel.totalChatUnread > 0:
            sidebarCountBadge(viewModel.totalChatUnread)
        case .calendar where viewModel.todaysUpcomingMeetingCount > 0:
            sidebarCountBadge(viewModel.todaysUpcomingMeetingCount)
        case .clipboard where !viewModel.clipboardEntries.isEmpty:
            sidebarCountBadge(viewModel.clipboardEntries.count)
        default:
            EmptyView()
        }
    }

    private func sidebarCountBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.2), in: Capsule())
    }
}
