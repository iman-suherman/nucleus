import NucleusCore
import NucleusUI
import SwiftUI

struct NotesWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var noteToOpen: NoteDocument?

    private var notes: [NoteDocument] {
        viewModel.regularNotes
    }

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    ContentUnavailableView {
                        Label("No notes yet", systemImage: "note.text")
                    } description: {
                        Text(emptyDescriptionText)
                    } actions: {
                        Button("New note") {
                            createNote()
                        }
                        Button("Refresh sync") {
                            Task { await viewModel.refreshICloudSync() }
                        }
                    }
                } else {
                    NotesListView(
                        notes: notes,
                        onSave: { try viewModel.saveNote($0) },
                        onDelete: { try viewModel.deleteNote($0) }
                    )
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MobileWorkspaceSettingsButton {
                        viewModel.openSettings()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.captureClipboardToNote() }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .disabled(!ClipboardCaptureService.hasContent())

                    Button {
                        createNote()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("notes.add")
                }
            }
            .navigationDestination(item: $noteToOpen) { note in
                NoteDetailView(
                    note: note,
                    onSave: { try viewModel.saveNote($0) },
                    onDelete: { note in
                        try viewModel.deleteNote(note)
                        noteToOpen = nil
                    }
                )
            }
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

    private func createNote() {
        do {
            noteToOpen = try viewModel.createNote(in: .notes)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private var emptyDescriptionText: String {
        if !viewModel.notesService.usesCloudKitSync {
            return viewModel.notesService.syncStatusMessage
        }
        if let name = viewModel.iCloudSync.accountName {
            return "Notes sync from your computer via cloud sync as \(name). Pull down to refresh."
        }
        if viewModel.iCloudSync.isSignedIn {
            return "Notes sync from your computer via cloud sync. Pull down to refresh — first import can take a minute."
        }
        return "Sign in to cloud sync in device Settings to sync notes from your computer."
    }
}

struct PasswordsWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var noteToOpen: NoteDocument?

    private var passwords: [NoteDocument] {
        viewModel.passwordNotes
    }

    var body: some View {
        NavigationStack {
            Group {
                if passwords.isEmpty {
                    ContentUnavailableView {
                        Label("No passwords yet", systemImage: "key.fill")
                    } description: {
                        Text(emptyDescriptionText)
                    } actions: {
                        Button("New password") {
                            createPassword()
                        }
                        Button("Refresh sync") {
                            Task { await viewModel.refreshICloudSync() }
                        }
                    }
                } else {
                    NotesListView(
                        notes: passwords,
                        onSave: { try viewModel.saveNote($0) },
                        onDelete: { try viewModel.deleteNote($0) }
                    )
                }
            }
            .navigationTitle("Passwords")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MobileWorkspaceSettingsButton {
                        viewModel.openSettings()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createPassword()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("passwords.add")
                }
            }
            .navigationDestination(item: $noteToOpen) { note in
                NoteDetailView(
                    note: note,
                    onSave: { try viewModel.saveNote($0) },
                    onDelete: { note in
                        try viewModel.deleteNote(note)
                        noteToOpen = nil
                    }
                )
            }
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

    private func createPassword() {
        do {
            noteToOpen = try viewModel.createNote(in: .passwords)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private var emptyDescriptionText: String {
        if !viewModel.notesService.usesCloudKitSync {
            return viewModel.notesService.syncStatusMessage
        }
        if let name = viewModel.iCloudSync.accountName {
            return "Password entries sync from your computer via cloud sync as \(name). Pull down to refresh."
        }
        if viewModel.iCloudSync.isSignedIn {
            return "Password entries sync from your computer via cloud sync. Pull down to refresh."
        }
        return "Sign in to cloud sync in device Settings to sync passwords from your computer."
    }
}

struct SettingsWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var deviceLock: MobileDeviceLockService
    @Environment(\.dismiss) private var dismiss
    @State private var emailNotifications = true
    @State private var chatNotifications = true
    @State private var calendarNotifications = true
    @State private var billNotificationsEnabled = true
    @State private var billNotificationHour = 7
    @State private var billNotifySevenDaysBefore = true
    @State private var billNotifyThreeDaysBefore = true
    @State private var billNotifyOneDayBefore = true
    @State private var billNotifyOnDueDate = true
    @State private var suppressSettingsPush = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloud account for notes") {
                    ICloudAccountDetailsView(syncService: viewModel.iCloudSync) {
                        Task { await viewModel.refreshICloudSync() }
                    }
                }

                Section("Sync") {
                    ICloudSyncStatusCard(
                        syncService: viewModel.iCloudSync,
                        notesService: viewModel.notesService,
                        primaryNotesAccountEmail: nil,
                        onRefresh: {
                            Task { await viewModel.refreshICloudSync() }
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Security") {
                    Toggle(deviceLock.biometricSettingLabel, isOn: $deviceLock.requireBiometrics)
                    Toggle("Require device passcode", isOn: $deviceLock.requirePasscode)

                    if deviceLock.isProtectionEnabled {
                        Label {
                            Text("Nucleus locks when you leave the app.")
                        } icon: {
                            Image(systemName: securityStatusIcon)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("App lock is off. Turn on biometric unlock or device passcode to protect your notes and passwords.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let message = deviceLock.lastErrorMessage, deviceLock.isProtectionEnabled {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Notifications") {
                    Toggle("Email notifications", isOn: $emailNotifications)
                    Toggle("Chat notifications", isOn: $chatNotifications)
                    Toggle("Calendar notifications", isOn: $calendarNotifications)
                    Text("Mail and chat push delivery requires the optional push backend. Calendar uses local reminders on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Bill reminders") {
                    Toggle("Bill due reminders", isOn: $billNotificationsEnabled)

                    Stepper(
                        "Notify at \(billNotificationHourLabel(billNotificationHour))",
                        value: $billNotificationHour,
                        in: 5...12
                    )
                    .disabled(!billNotificationsEnabled)

                    Toggle("7 days before due", isOn: $billNotifySevenDaysBefore)
                        .disabled(!billNotificationsEnabled)
                    Toggle("3 days before due", isOn: $billNotifyThreeDaysBefore)
                        .disabled(!billNotificationsEnabled)
                    Toggle("1 day before due", isOn: $billNotifyOneDayBefore)
                        .disabled(!billNotificationsEnabled)
                    Toggle("On due date", isOn: $billNotifyOnDueDate)
                        .disabled(!billNotificationsEnabled)

                    Text("Local notifications for active bills with an amount still due. Reminders reschedule automatically when bills change. Settings sync with your computer via cloud sync.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Notes sync") {
                    Text("Note content syncs through private cloud sync using the signed-in account on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                PublicHolidayLocationSettingsSection()
                PublicHolidayCountrySettingsSection(settings: MobilePublicHolidaySettings.shared)

                Section("About") {
                    LabeledContent("Version", value: mobileAppVersion)
                    Button("What's New in This Version") {
                        Task { await viewModel.presentCurrentReleaseNotes() }
                    }
                    LabeledContent("Tagline", value: NucleusAppBranding.tagline)
                    Text(NucleusAppBranding.mobileCompanionSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.closeSettings()
                        dismiss()
                    }
                }
            }
            .onAppear {
                applySyncedSettings()
                deviceLock.refreshAvailability()
                if !ProcessInfo.processInfo.arguments.contains("-screenshotMode") {
                    Task { await viewModel.refreshICloudSync() }
                }
            }
            .onChange(of: viewModel.settingsSync.syncedConfiguration) { _, _ in
                applySyncedSettings()
            }
            .onChange(of: emailNotifications) { _, _ in pushNotificationSettingsIfNeeded() }
            .onChange(of: chatNotifications) { _, _ in pushNotificationSettingsIfNeeded() }
            .onChange(of: calendarNotifications) { _, _ in pushNotificationSettingsIfNeeded() }
            .onChange(of: billNotificationsEnabled) { _, _ in pushNotificationSettingsIfNeeded() }
            .onChange(of: billNotificationHour) { _, _ in pushNotificationSettingsIfNeeded() }
            .onChange(of: billNotifySevenDaysBefore) { _, _ in pushNotificationSettingsIfNeeded() }
            .onChange(of: billNotifyThreeDaysBefore) { _, _ in pushNotificationSettingsIfNeeded() }
            .onChange(of: billNotifyOneDayBefore) { _, _ in pushNotificationSettingsIfNeeded() }
            .onChange(of: billNotifyOnDueDate) { _, _ in pushNotificationSettingsIfNeeded() }
        }
    }

    private var mobileAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    }

    private func applySyncedSettings() {
        guard let config = viewModel.settingsSync.syncedConfiguration else { return }
        suppressSettingsPush = true
        emailNotifications = config.emailNotificationsEnabled
        chatNotifications = config.chatNotificationsEnabled
        calendarNotifications = config.calendarNotificationsEnabled
        billNotificationsEnabled = config.billNotificationsEnabled
        billNotificationHour = config.billNotificationHour
        billNotifySevenDaysBefore = config.billNotifySevenDaysBefore
        billNotifyThreeDaysBefore = config.billNotifyThreeDaysBefore
        billNotifyOneDayBefore = config.billNotifyOneDayBefore
        billNotifyOnDueDate = config.billNotifyOnDueDate
        suppressSettingsPush = false
    }

    private func pushNotificationSettingsIfNeeded() {
        guard !suppressSettingsPush else { return }
        pushNotificationSettings()
    }

    private func pushNotificationSettings() {
        viewModel.pushNotificationPreferences(
            emailEnabled: emailNotifications,
            chatEnabled: chatNotifications,
            calendarEnabled: calendarNotifications,
            billConfiguration: BillDueReminderConfiguration(
                enabled: billNotificationsEnabled,
                hour: billNotificationHour,
                notifySevenDaysBefore: billNotifySevenDaysBefore,
                notifyThreeDaysBefore: billNotifyThreeDaysBefore,
                notifyOneDayBefore: billNotifyOneDayBefore,
                notifyOnDueDate: billNotifyOnDueDate
            ),
            iCloudKeychainTokenSyncEnabled: viewModel.settingsSync.syncedConfiguration?.iCloudKeychainTokenSyncEnabled ?? true
        )
    }

    private func billNotificationHourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    private var securityStatusIcon: String {
        switch deviceLock.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        default:
            return "lock.shield"
        }
    }
}
