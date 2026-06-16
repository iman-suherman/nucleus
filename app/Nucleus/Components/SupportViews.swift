import AppKit
import DatabaseKit
import NucleusKit
import SwiftUI
import SyncKit

struct QuickReplySheet: View {
    let context: QuickReplyContext
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var bodyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Reply")
                .font(.title2.bold())
            Text("To: \(context.to)")
                .foregroundStyle(.secondary)
            Text("Subject: \(context.subject)")
                .foregroundStyle(.secondary)

            TextEditor(text: $bodyText)
                .font(.body)
                .frame(minHeight: 160)
                .padding(8)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Send") {
                    Task {
                        await viewModel.sendQuickReply(body: bodyText)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

struct AppSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var syncService: CloudKitSyncService
    @ObservedObject var cloudSyncService: NucleusCloudSyncService
    @ObservedObject var viewModel: AppViewModel
    var accounts: [GoogleAccount]
    let selectedTab: SettingsTab
    @State private var cloudKitSyncMessage: String?
    @State private var isSyncingToCloudKit = false
    @State private var nucleusCloudMessage: String?
    @State private var isConnectingNucleusCloud = false
    @State private var isSyncingNucleusCloud = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTab.title)
                        .font(.title3.bold())
                    Text(selectedTab.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Form {
                    settingsContent(for: selectedTab)
                }
                .formStyle(.grouped)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .nucleusCloud:
            nucleusCloudSection
        case .iCloud:
            iCloudSyncSection
        case .keychain:
            iCloudKeychainSection
        case .notifications:
            notificationsSection
        case .mail:
            mailSection
        case .chat:
            chatSection
        case .about:
            aboutSection
        }
    }

    private var nucleusCloudSection: some View {
        Section("Nucleus Cloud") {
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    Image(systemName: cloudSyncService.status.isConnected ? "checkmark.circle" : "icloud.and.arrow.up")
                        .foregroundStyle(cloudSyncService.status.isConnected ? .green : .secondary)
                    Text(cloudSyncService.status.label)
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "Nucleus Cloud syncs notes, bills, dashboard analysis, settings, and account metadata without Apple iCloud. Google OAuth tokens stay in Keychain on this Mac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if cloudSyncService.status.isConnected {
                if let lastSyncAt = cloudSyncService.lastSyncAt {
                    LabeledContent("Last sync") {
                        Text(lastSyncAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(isSyncingNucleusCloud ? "Syncing…" : "Sync Now") {
                    isSyncingNucleusCloud = true
                    nucleusCloudMessage = "Syncing with Nucleus Cloud…"
                    Task {
                        nucleusCloudMessage = await viewModel.pushToNucleusCloud()
                        isSyncingNucleusCloud = false
                    }
                }
                .disabled(isSyncingNucleusCloud)

                Button("Disconnect", role: .destructive) {
                    cloudSyncService.disconnect()
                    nucleusCloudMessage = "Disconnected from Nucleus Cloud."
                }
            } else {
                Button(isConnectingNucleusCloud ? "Opening Browser…" : "Connect Account") {
                    isConnectingNucleusCloud = true
                    nucleusCloudMessage = "Authorize this Mac in your browser…"
                    Task {
                        nucleusCloudMessage = await viewModel.connectNucleusCloud()
                        isConnectingNucleusCloud = false
                    }
                }
                .disabled(isConnectingNucleusCloud)
            }

            if let nucleusCloudMessage {
                Text(nucleusCloudMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastError = cloudSyncService.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: cloudSyncService.status) { _, status in
            if case .connected = status, isConnectingNucleusCloud {
                nucleusCloudMessage = "Connected. Syncing your workspace…"
                isConnectingNucleusCloud = false
            }
        }
    }

    private var iCloudSyncSection: some View {
        Section("iCloud Sync") {
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    Image(systemName: syncService.status.isAvailable ? "checkmark.icloud" : "icloud.slash")
                        .foregroundStyle(syncService.status.isAvailable ? .green : .secondary)
                    Text(syncService.status.label)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Notes storage") {
                Text(NucleusDatabase.usesCloudKitSync ? "iCloud CloudKit" : "This Mac only")
                    .foregroundStyle(NucleusDatabase.usesCloudKitSync ? Color.secondary : Color.orange)
            }

            LabeledContent("Notes on this Mac") {
                Text("\(viewModel.notes.count)")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Bills on this Mac") {
                Text("\(viewModel.activeBills.count) bills, \(viewModel.billPayments.count) payments")
                    .foregroundStyle(.secondary)
            }

            if let analyzedAt = viewModel.dashboardAnalyzedAt {
                LabeledContent("Dashboard analysis") {
                    Text(analyzedAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            if !NucleusDatabase.usesCloudKitSync, let error = NucleusDatabase.lastCloudKitSetupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if NucleusDatabase.usesCloudKitSync {
                Text(
                    "In CloudKit Console, query Private Database → zone \(NucleusDatabase.swiftDataCloudKitZoneName) → record type CD_NoteRecord (not _defaultZone)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Button(syncToCloudButtonTitle) {
                        isSyncingToCloudKit = true
                        cloudKitSyncMessage = "Waiting for CloudKit export (up to 45s)…"
                        Task {
                            cloudKitSyncMessage = await viewModel.pushSyncedDataToCloudKit(force: true)
                            isSyncingToCloudKit = false
                        }
                    }
                    .disabled(isSyncingToCloudKit || !viewModel.hasSyncedDataToUpload)

                    if let cloudKitSyncMessage {
                        Text(cloudKitSyncMessage)
                            .font(.caption)
                            .foregroundStyle(cloudKitMessageColor(cloudKitSyncMessage))
                    }

                    Text("Syncs notes, bills, and the latest dashboard analysis to iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ICloudSyncLogPanel(syncService: syncService)
            }

            if let lastRemoteChangeAt = syncService.lastRemoteChangeAt {
                LabeledContent("Last update") {
                    Text(lastRemoteChangeAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Accounts, notes, bills, dashboard analysis, window layout, and preferences sync through iCloud. Gmail web sessions still require sign-in inside Inbox on each Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastExportError = syncService.lastCloudKitExportError {
                Text("Last export error: \(lastExportError)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Refresh iCloud Status") {
                Task { await syncService.refreshAccountStatus() }
            }
        }
    }

    private var iCloudKeychainSection: some View {
        Section("iCloud Keychain") {
            Toggle("Sync Google OAuth tokens", isOn: $settings.iCloudKeychainTokenSyncEnabled)

            Text("When enabled, Google refresh tokens sync through iCloud Keychain for automatic API reconnection on new Macs. Requires iCloud Keychain in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Refresh Credentials") {
                Task { await viewModel.autoReconnectAccounts(settings: settings) }
            }
        }
    }

    private var notificationsSection: some View {
        Group {
            Section("Notifications") {
                Toggle("Email notifications", isOn: $settings.emailNotificationsEnabled)
                Toggle("Chat notifications", isOn: $settings.chatNotificationsEnabled)
                Toggle("Calendar notifications", isOn: $settings.calendarNotificationsEnabled)
            }

            Section("Intelligent clipboard") {
                Toggle("Suggest saving passwords from clipboard", isOn: $settings.clipboardPasswordDetectionEnabled)

                Text("When Nucleus detects a password-like value on your clipboard, it offers to save it as a Passwords note.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hourly beep") {
                Toggle("Play beep every hour", isOn: $settings.hourlyBeepEnabled)

                Picker("Sound", selection: $settings.hourlyBeepSound) {
                    ForEach(HourlyBeepSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }

                Button("Play preview") {
                    settings.hourlyBeepSound.playAlert()
                }

                Text("A short beep at minute 59 each hour, like a Casio watch hourly signal. Nucleus must be running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Bill reminders") {
                Toggle("Bill due reminders", isOn: $settings.billNotificationsEnabled)

                Stepper(
                    "Notify at \(billNotificationHourLabel(settings.billNotificationHour))",
                    value: $settings.billNotificationHour,
                    in: 5...12
                )
                .disabled(!settings.billNotificationsEnabled)

                Toggle("7 days before due", isOn: $settings.billNotifySevenDaysBefore)
                    .disabled(!settings.billNotificationsEnabled)
                Toggle("3 days before due", isOn: $settings.billNotifyThreeDaysBefore)
                    .disabled(!settings.billNotificationsEnabled)
                Toggle("1 day before due", isOn: $settings.billNotifyOneDayBefore)
                    .disabled(!settings.billNotificationsEnabled)
                Toggle("On due date", isOn: $settings.billNotifyOnDueDate)
                    .disabled(!settings.billNotificationsEnabled)

                Text("Local macOS notifications for active bills with an amount still due. Reminders reschedule automatically when bills change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    private var mailSection: some View {
        Group {
            Section("Mail notifications") {
                if accounts.isEmpty {
                    Text("Add a mail account to choose notification sounds.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accounts) { account in
                        mailSoundRow(for: account)
                    }
                }

                Picker("Default for new accounts", selection: $settings.mailNotificationSound) {
                    ForEach(MailNotificationSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
            }

            Section("Sync") {
                Stepper(value: $settings.mailSyncInterval, in: 30...300, step: 30) {
                    Text("Mail sync every \(Int(settings.mailSyncInterval))s")
                }
            }
        }
    }

    private var chatSection: some View {
        Section("Chat notifications") {
            if accounts.isEmpty {
                Text("Add a Gmail account to choose chat notification sounds.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accounts) { account in
                    chatSoundRow(for: account)
                }
            }

            Picker("Default for new accounts", selection: $settings.chatNotificationSound) {
                ForEach(ChatNotificationSound.allCases) { sound in
                    Text(sound.label).tag(sound)
                }
            }

            Text("Chat uses a separate tone from mail. Notifications include the account name and unread count.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: AppSettings.currentAppVersion)
            LabeledContent("Tagline", value: "Personal Operating System for macOS")
        }
    }

    private func cloudKitMessageColor(_ message: String) -> Color {
        let lowered = message.lowercased()
        if lowered.contains("failed") || lowered.contains("did not upload") {
            return .red
        }
        if lowered.contains("has not finished") || lowered.contains("waiting") {
            return .orange
        }
        if lowered.contains("uploaded") || lowered.contains("already has") || lowered.contains("synced") {
            return .green
        }
        return .secondary
    }

    private var syncToCloudButtonTitle: String {
        if isSyncingToCloudKit {
            return "Syncing to iCloud…"
        }
        return "Sync to iCloud"
    }

    private func mailSoundRow(for account: GoogleAccount) -> some View {
        let binding = Binding(
            get: { settings.mailNotificationSound(for: account.id) },
            set: { settings.setMailNotificationSound($0, for: account.id) }
        )
        let accountLabel = account.displayName.isEmpty ? account.email : account.displayName

        return VStack(alignment: .leading, spacing: 8) {
            Picker(accountLabel, selection: binding) {
                ForEach(MailNotificationSound.allCases) { sound in
                    Text(sound.label).tag(sound)
                }
            }
            Button("Play preview") {
                binding.wrappedValue.playAlert()
            }
            .disabled(binding.wrappedValue == .silent)
        }
    }

    private func chatSoundRow(for account: GoogleAccount) -> some View {
        let binding = Binding(
            get: { settings.chatNotificationSound(for: account.id) },
            set: { settings.setChatNotificationSound($0, for: account.id) }
        )
        let accountLabel = account.displayName.isEmpty ? account.email : account.displayName

        return VStack(alignment: .leading, spacing: 8) {
            Picker(accountLabel, selection: binding) {
                ForEach(ChatNotificationSound.allCases) { sound in
                    Text(sound.label).tag(sound)
                }
            }
            Button("Play preview") {
                binding.wrappedValue.playAlert()
            }
            .disabled(binding.wrappedValue == .silent)
        }
    }
}

private struct ICloudSyncLogPanel: View {
    @ObservedObject var syncService: CloudKitSyncService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sync log")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Copy") {
                    copyLogToPasteboard()
                }
                .disabled(syncService.syncLogStore.entries.isEmpty)
                Button("Clear") {
                    syncService.clearSyncLog()
                }
                .disabled(syncService.syncLogStore.entries.isEmpty)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if syncService.syncLogStore.entries.isEmpty {
                        Text("CloudKit export, import, and remote-change events for notes and bills appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(syncService.syncLogStore.entries) { entry in
                            Text(entry.formattedLine)
                                .font(.caption.monospaced())
                                .foregroundStyle(color(for: entry.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func color(for level: CloudKitSyncLogEntry.Level) -> Color {
        switch level {
        case .info:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func copyLogToPasteboard() {
        let text = syncService.syncLogStore.entries
            .reversed()
            .map(\.formattedLine)
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case nucleusCloud
    case iCloud
    case keychain
    case notifications
    case mail
    case chat
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nucleusCloud: return "Nucleus Cloud"
        case .iCloud: return "iCloud"
        case .keychain: return "Keychain"
        case .notifications: return "Notifications"
        case .mail: return "Mail"
        case .chat: return "Chat"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .nucleusCloud: return "cloud"
        case .iCloud: return "icloud"
        case .keychain: return "key"
        case .notifications: return "bell"
        case .mail: return "envelope"
        case .chat: return "message"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .nucleusCloud:
            return "Cross-platform sync without Apple iCloud."
        case .iCloud:
            return "Sync accounts, notes, bills, and preferences across your Macs."
        case .keychain:
            return "Keep Google OAuth tokens available for automatic reconnection."
        case .notifications:
            return "Choose which alerts Nucleus can send and optional hourly beeps."
        case .mail:
            return "Notification sounds and background mail sync intervals."
        case .chat:
            return "Chat alert tones and per-account notification sounds."
        case .about:
            return "Version and app information."
        }
    }
}

struct SettingsWorkspaceView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var selectedTab: SettingsTab = .nucleusCloud

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            Divider()

            HStack(alignment: .top, spacing: 0) {
                settingsSidebar
                settingsDetail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title2.bold())
            Text("Configure sync, notifications, and app preferences.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsSidebarRow(for: tab)
                }
            }
            .padding(8)
        }
        .frame(width: 220)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.35),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .padding(.leading, 12)
        .padding(.vertical, 12)
    }

    private func settingsSidebarRow(for tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            Label(tab.title, systemImage: tab.systemImage)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private var settingsDetail: some View {
        AppSettingsView(
            settings: settings,
            syncService: viewModel.syncService,
            cloudSyncService: viewModel.cloudSyncService,
            viewModel: viewModel,
            accounts: viewModel.accounts,
            selectedTab: selectedTab
        )
        .background(Color(nsColor: .textBackgroundColor).opacity(0.18))
    }
}
