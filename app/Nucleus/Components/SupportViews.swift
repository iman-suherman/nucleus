import AppKit
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
    @ObservedObject var viewModel: AppViewModel
    var accounts: [GoogleAccount]
    let selectedTab: SettingsTab

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

            if let lastRemoteChangeAt = syncService.lastRemoteChangeAt {
                LabeledContent("Last update") {
                    Text(lastRemoteChangeAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Accounts, notes, clipboard history, window layout, and preferences sync through iCloud. Gmail web sessions still require sign-in inside Inbox on each Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Sync clipboard history", isOn: $settings.clipboardSyncEnabled)

            Toggle("Save clipboard to Notes", isOn: $settings.clipboardSaveToNotesEnabled)
                .disabled(!settings.clipboardSyncEnabled)

                Text("When enabled, each copied item is saved as a regular note (synced via iCloud) so it is not lost when history is trimmed.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        Section("Notifications") {
            Toggle("Email notifications", isOn: $settings.emailNotificationsEnabled)
            Toggle("Chat notifications", isOn: $settings.chatNotificationsEnabled)
            Toggle("Calendar notifications", isOn: $settings.calendarNotificationsEnabled)
        }
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

enum SettingsTab: String, CaseIterable, Identifiable {
    case iCloud
    case keychain
    case notifications
    case mail
    case chat
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .iCloud:
            return "Sync accounts, notes, clipboard, and preferences across your Macs."
        case .keychain:
            return "Keep Google OAuth tokens available for automatic reconnection."
        case .notifications:
            return "Choose which alerts Nucleus can send."
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

    @State private var selectedTab: SettingsTab = .iCloud

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
            viewModel: viewModel,
            accounts: viewModel.accounts,
            selectedTab: selectedTab
        )
        .background(Color(nsColor: .textBackgroundColor).opacity(0.18))
    }
}
