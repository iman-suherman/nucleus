import NucleusCore
import NucleusUI
import SwiftUI

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
    @State private var keychainSync = true

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("Note content syncs through iCloud CloudKit using the Apple ID on this device — not your Google account. Google accounts on Mac are only used for optional Drive backup when OAuth is connected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Nucleus for iPhone and iPad is the mobile companion for your notes — synced from Mac via iCloud. Mail, Calendar, and Chat remain on macOS where they work best.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                applySyncedSettings()
                Task { await viewModel.refreshICloudSync() }
            }
            .onChange(of: keychainSync) { _, _ in pushKeychainSetting() }
        }
    }

    private func applySyncedSettings() {
        guard let config = viewModel.settingsSync.syncedConfiguration else { return }
        keychainSync = config.iCloudKeychainTokenSyncEnabled
    }

    private func pushKeychainSetting() {
        viewModel.settingsSync.pushNotificationPreferences(
            emailEnabled: viewModel.settingsSync.syncedConfiguration?.emailNotificationsEnabled ?? true,
            chatEnabled: viewModel.settingsSync.syncedConfiguration?.chatNotificationsEnabled ?? true,
            calendarEnabled: viewModel.settingsSync.syncedConfiguration?.calendarNotificationsEnabled ?? true,
            iCloudKeychainTokenSyncEnabled: keychainSync
        )
    }
}
