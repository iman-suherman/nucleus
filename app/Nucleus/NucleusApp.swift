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

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            WindowLayoutController.shared.persistLayoutNow()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            WindowLayoutController.shared.persistLayoutNow()
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

    private var launchWindowSize: (width: Double, height: Double) {
        let layout = AppSettings.shared.windowLayout
        let width = layout.flatMap { $0.width > 0 ? $0.width : nil } ?? WindowLayoutMetrics.defaultWidth
        let height = layout.flatMap { $0.height > 0 ? $0.height : nil } ?? WindowLayoutMetrics.defaultHeight
        return (
            width: max(width, WindowLayoutMetrics.minWidth),
            height: max(height, WindowLayoutMetrics.minHeight)
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .defaultSize(width: launchWindowSize.width, height: launchWindowSize.height)
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
            .frame(minWidth: 920, minHeight: 680)
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
            .background(
                WindowLayoutAccessor { window in
                    WindowLayoutController.shared.attach(to: window)
                }
            )
            .background(MarketingScreenshotWindowConfigurator())
            .onAppear {
                MarketingScreenshotCapture.scheduleIfNeeded()
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
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var newsFeedService = DashboardNewsFeedService.shared
    @ObservedObject private var newsSpeechService = DashboardNewsSpeechService.shared
    @ObservedObject private var weatherService = DashboardWeatherService.shared
    @ObservedObject private var holidayService = DashboardPublicHolidayService.shared
    @ObservedObject private var tmuxSessionBrowser = TmuxSessionBrowser.shared

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
        .frame(minWidth: 920, minHeight: 680)
        .onAppear {
            viewModel.scheduleBootstrap(settings: appSettings)
        }
    }

    private var mainWorkspace: some View {
        ZStack {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(
                        min: appSettings.sidebarColumnMinWidth,
                        ideal: appSettings.sidebarColumnIdealWidth,
                        max: appSettings.sidebarColumnMaxWidth
                    )
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
        .overlay(alignment: .top) {
            if appSettings.dashboardPreferences.newsFeedEnabled,
               let alert = newsFeedService.breakingNewsAlert {
                DashboardBreakingNewsOverlay(
                    alert: alert,
                    speechService: newsSpeechService,
                    onOpenLink: {
                        newsSpeechService.stop()
                        newsFeedService.openBreakingNewsAlertLink()
                    },
                    onDismiss: {
                        newsSpeechService.stop()
                        newsFeedService.dismissBreakingNewsAlert()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
        .onChange(of: appSettings.menuBarEnabled) { _, _ in
            viewModel.menuBarController.applySettings(appSettings)
        }
        .onChange(of: viewModel.sidebarSelection) { _, selection in
            viewModel.sidebarSelectionDidChange(selection)
            EmbeddedWebViewRegistry.syncVisibility(activePane: activeWorkspacePane(from: selection))
        }
        .onAppear {
            EmbeddedWebViewRegistry.syncVisibility(activePane: activeWorkspacePane(from: viewModel.sidebarSelection))
            syncBreakingNewsFeed()
            tmuxSessionBrowser.startAutoRefresh()
        }
        .onChange(of: appSettings.dashboardPreferences.newsFeedEnabled) { _, _ in
            syncBreakingNewsFeed()
        }
        .onChange(of: appSettings.publicHolidayCountryCodes) { _, _ in
            syncBreakingNewsFeed()
        }
        .onChange(of: weatherService.locationSnapshot?.countryCode) { _, _ in
            syncBreakingNewsFeed()
        }
        .onChange(of: holidayService.nextHoliday?.countryCode) { _, _ in
            syncBreakingNewsFeed()
        }
        .modelContainer(viewModel.modelContainer)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showWhatsNew)
        .animation(.spring(response: 0.48, dampingFraction: 0.86), value: newsFeedService.breakingNewsAlert?.id)
    }

    private func syncBreakingNewsFeed() {
        let countryCodes = DashboardNewsFeedService.preferredCountryCodes(
            settings: appSettings,
            weatherCountryCode: weatherService.locationSnapshot?.countryCode,
            nextHolidayCountryCode: holidayService.nextHoliday?.countryCode
        )
        newsFeedService.syncAutoRefreshIfNeeded(
            enabled: appSettings.dashboardPreferences.newsFeedEnabled,
            countryCodes: countryCodes
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        let activePane = activeWorkspacePane(from: viewModel.sidebarSelection)

        ZStack {
            Group {
                if MarketingScreenshotMode.isActive, let activePane {
                    MarketingWorkspacePreview(pane: activePane)
                } else {
                    switch activePane {
                    case .dashboard:
                        DashboardWorkspaceView()
                    case .inbox:
                        MailWorkspaceView(isVisible: activePane == .inbox)
                    case .clipboard:
                        ClipboardWorkspaceView()
                    case .notes:
                        EmptyView()
                    case .bills:
                        BillsWorkspaceView()
                    case .media:
                        MediaWorkspaceView()
                    case .terminal:
                        TerminalWorkspaceView()
                    case .accounts:
                        AccountCenterView()
                    case .settings:
                        SettingsWorkspaceView()
                    case .none:
                        MailWorkspaceView(isVisible: activePane == .inbox)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(activePane == .notes ? 0 : 1)
            .allowsHitTesting(activePane != .notes)
            .accessibilityHidden(activePane == .notes)

            NotesWorkspaceView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(activePane == .notes && !MarketingScreenshotMode.isActive ? 1 : 0)
                .allowsHitTesting(activePane == .notes && !MarketingScreenshotMode.isActive)
                .accessibilityHidden(activePane != .notes || MarketingScreenshotMode.isActive)
        }
    }

    private func activeWorkspacePane(from selection: SidebarSelection) -> WorkspacePane? {
        if case .workspace(let pane) = selection {
            return pane
        }
        return nil
    }

    private var isCompactSidebar: Bool {
        appSettings.sidebarSize == .compact
    }

    private var sidebar: some View {
        List(selection: $viewModel.sidebarSelection) {
            Section {
                NucleusBrandMark(
                    logoSize: isCompactSidebar ? 32 : 44,
                    showText: !isCompactSidebar
                )
                .frame(maxWidth: .infinity, alignment: isCompactSidebar ? .center : .leading)
                .padding(.vertical, isCompactSidebar ? 2 : 4)
            }

            if isCompactSidebar {
                Section {
                    ForEach(viewModel.orderedWorkspacePanes) { pane in
                        sidebarSelectableRow(for: pane)
                            .tag(SidebarSelection.workspace(pane))
                    }
                    .onMove(perform: viewModel.moveWorkspacePane)

                    ForEach(WorkspacePane.utilityWorkspaces) { pane in
                        sidebarSelectableRow(for: pane)
                            .tag(SidebarSelection.workspace(pane))
                    }
                }
            } else {
                Section("Workspace") {
                    ForEach(viewModel.orderedWorkspacePanes) { pane in
                        sidebarSelectableRow(for: pane)
                            .tag(SidebarSelection.workspace(pane))
                    }
                    .onMove(perform: viewModel.moveWorkspacePane)
                }

                Section("System") {
                    ForEach(WorkspacePane.utilityWorkspaces) { pane in
                        sidebarSelectableRow(for: pane)
                            .tag(SidebarSelection.workspace(pane))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaPadding(.top, isCompactSidebar ? 20 : 28)
        .animation(.easeInOut(duration: 0.2), value: appSettings.sidebarSize)
        .animation(.easeInOut(duration: 0.2), value: appSettings.workspacePaneOrder.map(\.rawValue))
    }

    private func sidebarSelectableRow(for pane: WorkspacePane) -> some View {
        sidebarRow(for: pane)
            .padding(.vertical, isCompactSidebar ? 6 : 3)
            .padding(.horizontal, isCompactSidebar ? 4 : 8)
            .frame(maxWidth: .infinity, alignment: isCompactSidebar ? .center : .leading)
            .pointerCursor()
            .help(isCompactSidebar ? "\(pane.title) — \(pane.subtitle)" : "")
            .listRowInsets(
                EdgeInsets(
                    top: 2,
                    leading: isCompactSidebar ? 4 : 8,
                    bottom: 2,
                    trailing: isCompactSidebar ? 4 : 8
                )
            )
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func sidebarRow(for pane: WorkspacePane) -> some View {
        if isCompactSidebar {
            compactSidebarRow(for: pane)
        } else {
            regularSidebarRow(for: pane)
        }
    }

    private func regularSidebarRow(for pane: WorkspacePane) -> some View {
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
                .allowsHitTesting(false)
        }
    }

    private func compactSidebarRow(for pane: WorkspacePane) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: pane.icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)

            compactBadge(for: pane)
                .offset(x: 8, y: -6)
        }
        .accessibilityLabel(pane.title)
        .accessibilityHint(pane.subtitle)
    }

    @ViewBuilder
    private func compactBadge(for pane: WorkspacePane) -> some View {
        if MarketingScreenshotMode.isActive {
            marketingCompactBadge(for: pane)
        } else {
            switch pane {
            case .dashboard where viewModel.totalUnread + viewModel.billsDueDockBadgeCount > 0:
                compactCountBadge(viewModel.totalUnread + viewModel.billsDueDockBadgeCount)
            case .inbox where viewModel.totalUnread > 0:
                compactCountBadge(viewModel.totalUnread, kind: .mail)
            case .clipboard where !viewModel.clipboardEntries.isEmpty:
                compactCountBadge(viewModel.clipboardEntries.count)
            case .bills where !viewModel.activeBills.isEmpty:
                compactCountBadge(viewModel.activeBills.count)
            case .notes where viewModel.regularNotesCount + viewModel.passwordNotesCount > 0:
                compactCountBadge(viewModel.regularNotesCount + viewModel.passwordNotesCount)
            case .terminal where tmuxSessionBrowser.activeSessionCount > 0:
                compactCountBadge(tmuxSessionBrowser.activeSessionCount)
            case .media where mediaController.nowPlaying.isPlaying:
                Image(systemName: "waveform")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(3)
                    .background(.green.opacity(0.15), in: Circle())
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func marketingCompactBadge(for pane: WorkspacePane) -> some View {
        if MarketingScreenshotMode.showsMusicPlayingBadge, pane == .media {
            Image(systemName: "waveform")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.green)
                .padding(3)
                .background(.green.opacity(0.15), in: Circle())
        } else if let count = MarketingScreenshotMode.demoBadgeCount(for: pane) {
            compactCountBadge(count, kind: pane == .inbox ? .mail : .neutral)
        } else if let badges = MarketingScreenshotMode.demoNoteBadges(for: pane) {
            compactCountBadge(badges.notes + badges.passwords)
        } else {
            EmptyView()
        }
    }

    private func compactCountBadge(_ count: Int, kind: NucleusBadgeKind = .neutral) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(kind == .neutral ? kind.foreground : .white)
            .background(
                kind == .mail ? Color.blue.opacity(0.85) : kind.background,
                in: Capsule()
            )
    }

    @ViewBuilder
    private func badge(for pane: WorkspacePane) -> some View {
        if MarketingScreenshotMode.isActive {
            marketingBadge(for: pane)
        } else {
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
            case .notes where viewModel.regularNotesCount > 0 || viewModel.passwordNotesCount > 0:
                NoteFolderCountBadges(
                    notesCount: viewModel.regularNotesCount,
                    passwordsCount: viewModel.passwordNotesCount
                )
            case .terminal where tmuxSessionBrowser.activeSessionCount > 0:
                NucleusCountBadge(count: tmuxSessionBrowser.activeSessionCount)
            case .media where mediaController.nowPlaying.isPlaying:
                MusicPlayingSidebarIndicator()
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func marketingBadge(for pane: WorkspacePane) -> some View {
        if MarketingScreenshotMode.showsMusicPlayingBadge, pane == .media {
            MusicPlayingSidebarIndicator()
        } else if let badges = MarketingScreenshotMode.demoNoteBadges(for: pane) {
            NoteFolderCountBadges(
                notesCount: badges.notes,
                passwordsCount: badges.passwords
            )
        } else if let count = MarketingScreenshotMode.demoBadgeCount(for: pane) {
            NucleusCountBadge(count: count, kind: pane == .inbox ? .mail : .neutral)
        } else {
            EmptyView()
        }
    }
}
