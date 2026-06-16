import AppKit
import NucleusKit
import SwiftUI
import SwiftData
import SyncKit

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

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: .nucleusDidOpenURL, object: url)
        }
    }
}

@main
struct NucleusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var appSettings = AppSettings.shared

    var body: some Scene {
        mainWindowScene
        menuBarScene
    }

    private var mainWindowScene: some Scene {
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
                    viewModel.refreshMailUnreadNow()
                }
                .onOpenURL { url in
                    Task { await viewModel.handleIncomingURL(url) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .nucleusDidOpenURL)) { notification in
                    guard let url = notification.object as? URL else { return }
                    Task { await viewModel.handleIncomingURL(url) }
                }
                .background(
                    WindowLayoutAccessor { window in
                        WindowLayoutController.shared.attach(to: window)
                    }
                )
        }
        .defaultSize(width: 1320, height: 880)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    SparkleUpdaterController.shared.checkForUpdates()
                }
                Button("What's New in This Version") {
                    Task { await viewModel.presentCurrentReleaseNotes() }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    viewModel.sidebarSelection = .workspace(.settings)
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
    }

    @SceneBuilder
    private var menuBarScene: some Scene {
        MenuBarExtra(
            "Nucleus",
            systemImage: "doc.on.clipboard",
            isInserted: Binding(
                get: { appSettings.menuBarEnabled },
                set: { appSettings.menuBarEnabled = $0 }
            )
        ) {
            MenuBarPopoverView(controller: viewModel.menuBarController)
                .onAppear { viewModel.menuBarController.reload() }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct WindowToolbarChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbarBackground(.regularMaterial, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        Group {
            if viewModel.isStartingUp {
                StartupSplashOverlay(
                    version: AppSettings.currentAppVersion,
                    currentMessage: viewModel.startupMessage,
                    completedSteps: viewModel.startupCompletedSteps,
                    activeStep: viewModel.startupActiveStep,
                    progressFraction: viewModel.startupProgressFraction
                )
            } else {
                mainWorkspace
            }
        }
        .frame(minWidth: 1180, minHeight: 780)
        .animation(.easeInOut(duration: 0.22), value: viewModel.isStartingUp)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showWhatsNew)
    }

    private var mainWorkspace: some View {
        ZStack {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 260, ideal: appSettings.sidebarWidth, max: 340)
            } detail: {
                detailContent
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WorkspaceStatusBadge(
                        message: viewModel.statusMessage,
                        mailUnreadCount: viewModel.totalUnread,
                        chatUnreadCount: viewModel.totalChatUnread,
                        mailAccounts: viewModel.unreadBreakdown(for: viewModel.unreadByAccount),
                        chatAccounts: viewModel.unreadBreakdown(for: viewModel.chatUnreadByAccount)
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
            .modifier(WindowToolbarChromeModifier())

            if viewModel.showWhatsNew, let release = viewModel.whatsNewRelease {
                WhatsNewOverlay(release: release) {
                    viewModel.dismissWhatsNew()
                }
            }

            ForEach(viewModel.webSessionAccounts) { account in
                GmailUnreadPoller(accountID: account.id, accountEmail: account.email)
                ChatUnreadPoller(accountID: account.id)
            }
        }
        .onChange(of: appSettings.menuBarEnabled) { _, enabled in
            viewModel.menuBarController.applySettings(appSettings)
            if enabled {
                viewModel.menuBarController.reload()
            }
        }
        .onChange(of: viewModel.sidebarSelection) { _, selection in
            viewModel.sidebarSelectionDidChange(selection)
            EmbeddedWebViewRegistry.syncVisibility(activePane: activeWorkspacePane(from: selection))
        }
        .onAppear {
            EmbeddedWebViewRegistry.syncVisibility(activePane: activeWorkspacePane(from: viewModel.sidebarSelection))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch activeWorkspacePane(from: viewModel.sidebarSelection) {
            case .dashboard:
                DashboardWorkspaceView()
            case .inbox:
                MailWorkspaceView(isVisible: true)
            case .calendar:
                CalendarWorkspaceView(isVisible: true)
            case .chat:
                ChatWorkspaceView(isVisible: true)
            case .clipboard:
                ClipboardWorkspaceView()
            case .notes:
                NotesWorkspaceView()
            case .bills:
                BillsWorkspaceView()
            case .accounts:
                AccountCenterView()
            case .settings:
                SettingsWorkspaceView()
            case .none:
                MailWorkspaceView(isVisible: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activeWorkspacePane(from selection: SidebarSelection) -> WorkspacePane? {
        if case .workspace(let pane) = selection {
            return pane
        }
        return nil
    }

    private var sidebar: some View {
        List(selection: $viewModel.sidebarSelection) {
            Section {
                NucleusBrandMark(logoSize: 44, showText: true)
                    .padding(.vertical, 4)
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
        .safeAreaPadding(.top, 28)
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
        case .dashboard where viewModel.totalUnread + viewModel.totalChatUnread + viewModel.billsDueDockBadgeCount > 0:
            NucleusCountBadge(
                count: viewModel.totalUnread + viewModel.totalChatUnread + viewModel.billsDueDockBadgeCount
            )
        case .inbox where viewModel.totalUnread > 0:
            NucleusCountBadge(count: viewModel.totalUnread, kind: .mail)
        case .chat where viewModel.totalChatUnread > 0:
            NucleusCountBadge(count: viewModel.totalChatUnread, kind: .chat)
        case .clipboard where !viewModel.clipboardEntries.isEmpty:
            NucleusCountBadge(count: viewModel.clipboardEntries.count)
        case .bills where !viewModel.activeBills.isEmpty:
            NucleusCountBadge(count: viewModel.activeBills.count)
        default:
            EmptyView()
        }
    }
}
