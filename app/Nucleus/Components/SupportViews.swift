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

    @State private var selectedTab: SettingsTab = .iCloud

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsTab(.iCloud) {
                iCloudSyncSection
            }

            settingsTab(.keychain) {
                iCloudKeychainSection
            }

            settingsTab(.notifications) {
                notificationsSection
            }

            settingsTab(.mail) {
                mailSection
            }

            settingsTab(.about) {
                aboutSection
            }
        }
        .padding(.horizontal, 24)
    }

    private func settingsTab<Content: View>(
        _ tab: SettingsTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            Form {
                content()
            }
            .formStyle(.grouped)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
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
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case iCloud
    case keychain
    case notifications
    case mail
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloud: return "iCloud"
        case .keychain: return "Keychain"
        case .notifications: return "Notifications"
        case .mail: return "Mail"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .iCloud: return "icloud"
        case .keychain: return "key"
        case .notifications: return "bell"
        case .mail: return "envelope"
        case .about: return "info.circle"
        }
    }
}

struct SettingsWorkspaceView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.title2.bold())
                Text("Configure sync, notifications, and app preferences.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            AppSettingsView(
                settings: settings,
                syncService: viewModel.syncService,
                viewModel: viewModel,
                accounts: viewModel.accounts
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
