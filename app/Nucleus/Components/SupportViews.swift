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

    var body: some View {
        Form {
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

                Button("Refresh iCloud Status") {
                    Task { await syncService.refreshAccountStatus() }
                }
            }

            Section("iCloud Keychain") {
                Toggle("Sync Google OAuth tokens", isOn: $settings.iCloudKeychainTokenSyncEnabled)

                Text("When enabled, Google refresh tokens sync through iCloud Keychain for automatic API reconnection on new Macs. Requires iCloud Keychain in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Refresh Credentials") {
                    Task { await viewModel.autoReconnectAccounts(settings: settings) }
                }
            }

            Section("Notifications") {
                Toggle("Email notifications", isOn: $settings.emailNotificationsEnabled)
                Toggle("Calendar notifications", isOn: $settings.calendarNotificationsEnabled)
            }

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

            Section("About") {
                LabeledContent("Version", value: AppSettings.currentAppVersion)
                LabeledContent("Tagline", value: "Personal Operating System for macOS")
            }
        }
        .formStyle(.grouped)
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

struct SettingsWorkspaceView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(.title2.bold())
                    Text("Configure iCloud sync, notification preferences, clipboard sync, and mail sounds.")
                        .foregroundStyle(.secondary)
                }

                AppSettingsView(
                    settings: settings,
                    syncService: viewModel.syncService,
                    viewModel: viewModel,
                    accounts: viewModel.accounts
                )
                    .frame(maxWidth: 560, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
