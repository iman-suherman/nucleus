import NucleusCore
import NucleusUI
import SwiftUI

struct MailWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel

    var body: some View {
        WorkspaceScreen(surface: .mail, title: "Mail") {
            if let account = currentAccount {
                WorkspaceWebView(
                    accountID: account.id,
                    accountEmail: account.email,
                    surface: .mail,
                    isVisible: true
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var currentAccount: GoogleAccount? {
        guard let id = viewModel.selectedAccountID(for: .mail) else { return nil }
        return viewModel.accountService.accounts.first(where: { $0.id == id })
    }
}

struct ChatWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel

    var body: some View {
        WorkspaceScreen(surface: .chat, title: "Chat") {
            if let account = currentAccount {
                WorkspaceWebView(
                    accountID: account.id,
                    accountEmail: account.email,
                    surface: .chat,
                    isVisible: true
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var currentAccount: GoogleAccount? {
        guard let id = viewModel.selectedAccountID(for: .chat) else { return nil }
        return viewModel.accountService.accounts.first(where: { $0.id == id })
    }
}

struct CalendarWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var showWebCalendar = false

    var body: some View {
        WorkspaceScreen(surface: .calendar, title: "Calendar") {
            if showWebCalendar, let account = currentAccount {
                WorkspaceWebView(
                    accountID: account.id,
                    accountEmail: account.email,
                    surface: .calendar,
                    isVisible: true,
                    onSignedIn: {
                        Task { await viewModel.refreshCalendar() }
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                CalendarDashboardView(
                    events: viewModel.calendarSync.upcomingEvents(),
                    isSyncing: viewModel.calendarSync.isSyncing,
                    onRefresh: {
                        Task { await viewModel.refreshCalendar() }
                    }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showWebCalendar ? "Dashboard" : "Web") {
                    showWebCalendar.toggle()
                }
            }
        }
    }

    private var currentAccount: GoogleAccount? {
        guard let id = viewModel.selectedAccountID(for: .calendar) else { return nil }
        return viewModel.accountService.accounts.first(where: { $0.id == id })
    }
}

struct NotesWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.notesService.notes.isEmpty {
                    ContentUnavailableView {
                        Label("No notes yet", systemImage: "note.text")
                    } description: {
                        emptyNotesDescription
                    } actions: {
                        Button("Refresh from iCloud") {
                            Task { await viewModel.refreshICloudSync() }
                        }
                    }
                } else {
                    NotesListView(notes: viewModel.notesService.notes) { note in
                        try viewModel.notesService.saveNote(note)
                    }
                }
            }
            .navigationTitle("Notes")
            .safeAreaInset(edge: .bottom) {
                NotesSyncFooter(
                    syncService: viewModel.iCloudSync,
                    notesService: viewModel.notesService
                )
            }
            .refreshable {
                await viewModel.refreshICloudSync()
            }
        }
    }

    private var emptyNotesDescription: Text {
        if !viewModel.notesService.usesCloudKitSync {
            return Text(viewModel.notesService.syncStatusMessage)
        }
        if let name = viewModel.iCloudSync.accountName {
            return Text("Notes sync from your Mac via iCloud as \(name). Pull down to refresh.")
        }
        if viewModel.iCloudSync.isSignedIn {
            return Text("Notes sync from your Mac via iCloud. Pull down to refresh — first import can take a minute.")
        }
        return Text(
            "Sign in to iCloud in Settings → Apple ID → iCloud to sync notes from your Mac."
        )
    }
}

struct SettingsWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var emailNotifications = true
    @State private var chatNotifications = true
    @State private var calendarNotifications = true
    @State private var keychainSync = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Accounts") {
                    ForEach(viewModel.accountService.accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.displayName)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if account.isPrimary {
                                Text("Primary")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Add account") {
                        viewModel.showAddAccount = true
                    }
                }

                Section("Notifications") {
                    Toggle("Email", isOn: $emailNotifications)
                    Toggle("Chat", isOn: $chatNotifications)
                    Toggle("Calendar reminders", isOn: $calendarNotifications)
                }

                Section("iCloud account for notes") {
                    ICloudAccountDetailsView(syncService: viewModel.iCloudSync) {
                        Task { await viewModel.refreshICloudSync() }
                    }
                }

                Section("Sync") {
                    ICloudSyncStatusCard(
                        syncService: viewModel.iCloudSync,
                        notesService: viewModel.notesService,
                        primaryNotesAccountEmail: viewModel.primaryNotesAccountEmail,
                        onRefresh: {
                            Task { await viewModel.refreshICloudSync() }
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Toggle("Sync OAuth tokens via iCloud Keychain", isOn: $keychainSync)
                }

                Section("Notes sync") {
                    Text("Note content syncs through iCloud CloudKit using the Apple ID on this device — not your Google account. Google accounts are only used for optional Drive backup on Mac when OAuth is connected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Nucleus for iPhone and iPad is the mobile companion to your personal operating system: quick access to your Google workspace, synced settings, meeting alerts, notes capture, and account-aware notifications.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                applySyncedSettings()
                Task { await viewModel.refreshICloudSync() }
            }
            .onChange(of: emailNotifications) { _, _ in pushNotificationSettings() }
            .onChange(of: chatNotifications) { _, _ in pushNotificationSettings() }
            .onChange(of: calendarNotifications) { _, _ in pushNotificationSettings() }
            .onChange(of: keychainSync) { _, _ in pushNotificationSettings() }
        }
    }

    private func applySyncedSettings() {
        guard let config = viewModel.settingsSync.syncedConfiguration else { return }
        emailNotifications = config.emailNotificationsEnabled
        chatNotifications = config.chatNotificationsEnabled
        calendarNotifications = config.calendarNotificationsEnabled
        keychainSync = config.iCloudKeychainTokenSyncEnabled
    }

    private func pushNotificationSettings() {
        viewModel.settingsSync.pushNotificationPreferences(
            emailEnabled: emailNotifications,
            chatEnabled: chatNotifications,
            calendarEnabled: calendarNotifications,
            iCloudKeychainTokenSyncEnabled: keychainSync
        )
    }
}

private struct WorkspaceScreen<Content: View>: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    let surface: WebSurface
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.accountService.accounts.isEmpty {
                    EmptyAccountsPrompt {
                        viewModel.showAddAccount = true
                    }
                } else {
                    content()
                }
            }
            .navigationTitle(title)
            .toolbar {
                if !viewModel.accountService.accounts.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        AccountPickerMenu(
                            accounts: viewModel.accountService.accounts,
                            selectedAccountID: viewModel.selectedAccountID(for: surface),
                            onSelect: { viewModel.selectAccount($0, for: surface) }
                        )
                    }
                }
            }
        }
    }
}
