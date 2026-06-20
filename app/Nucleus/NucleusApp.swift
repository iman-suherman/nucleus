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
            Self.kickBootstrap(attempt: 0)
        }
    }

    private static func kickBootstrap(attempt: Int) {
        Task { @MainActor in
            guard let viewModel = AppViewModel.current else {
                guard attempt < 100 else {
                    NSLog("Nucleus: bootstrap aborted — AppViewModel never became available")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    kickBootstrap(attempt: attempt + 1)
                }
                return
            }
            viewModel.scheduleBootstrap(settings: AppSettings.shared)
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

    var body: some Scene {
        WindowGroup {
            AppRootView()
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
                    Task { await AppViewModel.current?.presentCurrentReleaseNotes() }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppViewModel.current?.sidebarSelection = .workspace(.settings)
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
}

/// Hosts AppViewModel below the App scene layer so @Published updates during launch
/// do not rebuild the WindowGroup scene on every data reload.
private struct AppRootView: View {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var appSettings = AppSettings.shared

    var body: some View {
        ContentView()
            .environmentObject(viewModel)
            .environmentObject(appSettings)
            .frame(minWidth: 1180, minHeight: 780)
            .sheet(item: $viewModel.quickReplyContext) { context in
                QuickReplySheet(context: context)
                    .environmentObject(viewModel)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewModel.checkForUpdatesWhenEligible()
                viewModel.refreshMailUnreadNow()
                ClipboardPasteController.shared.refreshEventTapIfNeeded()
            }
            .onOpenURL { url in
                Task { await viewModel.handleIncomingURL(url) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nucleusDidOpenURL)) { notification in
                guard let url = notification.object as? URL else { return }
                Task { await viewModel.handleIncomingURL(url) }
            }
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
        .onAppear {
            viewModel.scheduleBootstrap(settings: appSettings)
        }
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
                        mailAccounts: viewModel.unreadBreakdown(for: viewModel.unreadByAccount)
                    )
                }
                ToolbarItem(placement: .automatic) {
                    MediaMiniPlayer()
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
            }
        }
        .background(
            WindowLayoutAccessor { window in
                WindowLayoutController.shared.attach(to: window)
            }
        )
        .onChange(of: appSettings.menuBarEnabled) { _, _ in
            viewModel.menuBarController.applySettings(appSettings)
        }
        .onChange(of: viewModel.sidebarSelection) { _, selection in
            viewModel.sidebarSelectionDidChange(selection)
            EmbeddedWebViewRegistry.syncVisibility(activePane: activeWorkspacePane(from: selection))
        }
        .onAppear {
            EmbeddedWebViewRegistry.syncVisibility(activePane: activeWorkspacePane(from: viewModel.sidebarSelection))
        }
        .modelContainer(viewModel.modelContainer)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showWhatsNew)
    }

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch activeWorkspacePane(from: viewModel.sidebarSelection) {
            case .dashboard:
                DashboardWorkspaceView()
            case .inbox:
                MailWorkspaceView(isVisible: true)
            case .clipboard:
                ClipboardWorkspaceView()
            case .notes:
                NotesWorkspaceView()
            case .bills:
                BillsWorkspaceView()
            case .media:
                MediaWorkspaceView()
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
        case .dashboard where viewModel.totalUnread + viewModel.billsDueDockBadgeCount > 0:
            NucleusCountBadge(
                count: viewModel.totalUnread + viewModel.billsDueDockBadgeCount
            )
        case .inbox where viewModel.totalUnread > 0:
            NucleusCountBadge(count: viewModel.totalUnread, kind: .mail)
        case .clipboard where !viewModel.clipboardEntries.isEmpty:
            NucleusCountBadge(count: viewModel.clipboardEntries.count)
        case .bills where !viewModel.activeBills.isEmpty:
            NucleusCountBadge(count: viewModel.activeBills.count)
        default:
            EmptyView()
        }
    }
}
