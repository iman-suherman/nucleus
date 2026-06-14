import AccountKit
import NucleusKit
import SwiftUI

struct AccountCenterView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                accountsList
                oauthSettings
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account Center")
                .font(.title2.bold())
            Text("Manage multiple Google identities, default inbox, and notes storage account.")
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.addGoogleAccount(settings: settings) }
            } label: {
                Label("Add Google Account", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(GoogleOAuthCoordinator.shared.isAuthenticating)

            if let oauthError = viewModel.oauthError {
                Text(oauthError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
                        onSetPrimary: { viewModel.setPrimaryAccount(account) },
                        onSetNotesAccount: { viewModel.setPrimaryNotesAccount(account) },
                        onRemove: { viewModel.removeAccount(account) }
                    )
                }
            }
        }
    }

    private var oauthSettings: some View {
        GroupBox("Google OAuth") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Client ID", text: $settings.googleClientID)
                SecureField("Client Secret (optional for desktop OAuth)", text: $settings.googleClientSecret)
                Text("Create a Desktop OAuth client in Google Cloud Console and register redirect URI net.suherman.nucleus:/oauth2redirect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .padding(8)
        }
    }
}

private struct AccountCard: View {
    let account: GoogleAccount
    let unreadCount: Int
    let onSetPrimary: () -> Void
    let onSetNotesAccount: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.headline)
                    Text(account.email)
                        .foregroundStyle(.secondary)
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
                if account.isPrimary {
                    Label("Primary inbox", systemImage: "star.fill")
                        .font(.caption)
                } else {
                    Button("Set Primary", action: onSetPrimary)
                        .buttonStyle(.borderless)
                }

                if account.isPrimaryNotesAccount {
                    Label("Notes account", systemImage: "note.text")
                        .font(.caption)
                } else {
                    Button("Use for Notes", action: onSetNotesAccount)
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
