import NucleusKit
import SwiftUI
import SyncKit

struct AccountCenterView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var isAddingWebAccount = false
    @State private var webAccountEmail = ""
    @State private var webAccountCategory = ""
    @State private var isConnectingNucleusCloud = false
    @State private var nucleusCloudMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                nucleusCloudCard
                accountsList
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var nucleusCloudCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.cloudSyncService.status.isConnected ? "checkmark.circle.fill" : "cloud")
                    .foregroundStyle(viewModel.cloudSyncService.status.isConnected ? .green : .secondary)
                Text("Nucleus Cloud")
                    .font(.headline)
            }

            Text(
                viewModel.cloudSyncService.status.isConnected
                    ? "This Mac syncs notes, bills, settings, and dashboard data through Nucleus Cloud."
                    : "Connect Nucleus Cloud to sync your workspace without Apple iCloud. Google OAuth tokens stay in Keychain on this Mac."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if viewModel.cloudSyncService.status.isConnected {
                Text(viewModel.cloudSyncService.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(isConnectingNucleusCloud ? "Opening Browser…" : "Connect Nucleus Cloud") {
                    isConnectingNucleusCloud = true
                    nucleusCloudMessage = "Authorize this Mac in your browser…"
                    Task {
                        nucleusCloudMessage = await viewModel.connectNucleusCloud()
                        isConnectingNucleusCloud = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnectingNucleusCloud)
            }

            if let nucleusCloudMessage {
                Text(nucleusCloudMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.45),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account Center")
                .font(.title2.bold())
            Text("Manage Google identities, Nucleus Cloud sync, and default inbox.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    isAddingWebAccount = true
                } label: {
                    Label("Add Gmail (Web Sign-In)", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Account metadata can sync via Nucleus Cloud or iCloud. OAuth tokens can sync via iCloud Keychain. Gmail web views still need sign-in inside Inbox on each Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let accountError = viewModel.accountError {
                Text(accountError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $isAddingWebAccount) {
            AddWebGmailAccountSheet(
                email: $webAccountEmail,
                categoryName: $webAccountCategory,
                onSubmit: {
                    viewModel.addWebGmailAccount(email: webAccountEmail, categoryName: webAccountCategory)
                    isAddingWebAccount = false
                },
                onCancel: { isAddingWebAccount = false }
            )
        }
    }

    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Accounts")
                .font(.headline)

            if viewModel.accounts.isEmpty {
                Text("No accounts connected yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.accounts) { account in
                    AccountCard(
                        account: account,
                        unreadCount: viewModel.unreadByAccount[account.id] ?? 0,
                        needsReconnect: viewModel.needsReconnect(for: account),
                        isOAuthConnected: viewModel.isOAuthConnected(account),
                        onSetPrimary: { viewModel.setPrimaryAccount(account) },
                        onRename: { viewModel.updateAccountCategory(account, name: $0) },
                        onReconnect: { viewModel.reconnectAccount(account) },
                        onRemove: { viewModel.removeAccount(account) }
                    )
                }
            }
        }
    }
}

private struct AccountCard: View {
    let account: GoogleAccount
    let unreadCount: Int
    let needsReconnect: Bool
    let isOAuthConnected: Bool
    let onSetPrimary: () -> Void
    let onRename: (String) -> Void
    let onReconnect: () -> Void
    let onRemove: () -> Void

    @State private var categoryName: String

    init(
        account: GoogleAccount,
        unreadCount: Int,
        needsReconnect: Bool,
        isOAuthConnected: Bool,
        onSetPrimary: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onReconnect: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.account = account
        self.unreadCount = unreadCount
        self.needsReconnect = needsReconnect
        self.isOAuthConnected = isOAuthConnected
        self.onSetPrimary = onSetPrimary
        self.onRename = onRename
        self.onReconnect = onReconnect
        self.onRemove = onRemove
        _categoryName = State(initialValue: account.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Category", text: $categoryName)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .onSubmit { onRename(categoryName) }
                    Text(account.email)
                        .foregroundStyle(.secondary)
                    if isOAuthConnected {
                        Label("API connected via iCloud Keychain", systemImage: "key.icloud.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if account.authMode == .webSession {
                        if needsReconnect {
                            Label("Needs Gmail sign-in on this Mac", systemImage: "exclamationmark.circle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Signed in on this Mac")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if isOAuthConnected {
                        Text("OAuth session active")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if unreadCount > 0 {
                    Text("\(unreadCount) unread")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
            }

            HStack {
                if needsReconnect {
                    Button("Reconnect in Inbox", action: onReconnect)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                if account.isPrimary {
                    Label("Primary inbox", systemImage: "star.fill")
                        .font(.caption)
                } else {
                    Button("Set Primary", action: onSetPrimary)
                        .buttonStyle(.borderless)
                }

                Spacer()
                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.borderless)
            }
            .font(.caption)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}
