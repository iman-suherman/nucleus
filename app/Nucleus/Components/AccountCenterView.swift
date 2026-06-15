import NucleusKit
import SwiftUI

struct AccountCenterView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var isAddingWebAccount = false
    @State private var webAccountEmail = ""
    @State private var webAccountCategory = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                accountsList
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

            HStack(spacing: 12) {
                Button {
                    isAddingWebAccount = true
                } label: {
                    Label("Add Gmail (Web Sign-In)", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Sign in to Gmail inside Inbox for each category. Web sign-in works for personal, work, and school Google accounts.")
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
                        onSetPrimary: { viewModel.setPrimaryAccount(account) },
                        onSetNotesAccount: { viewModel.setPrimaryNotesAccount(account) },
                        onRename: { viewModel.updateAccountCategory(account, name: $0) },
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
    let onSetPrimary: () -> Void
    let onSetNotesAccount: () -> Void
    let onRename: (String) -> Void
    let onRemove: () -> Void

    @State private var categoryName: String

    init(
        account: GoogleAccount,
        unreadCount: Int,
        onSetPrimary: @escaping () -> Void,
        onSetNotesAccount: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.account = account
        self.unreadCount = unreadCount
        self.onSetPrimary = onSetPrimary
        self.onSetNotesAccount = onSetNotesAccount
        self.onRename = onRename
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
                    if account.authMode == .webSession {
                        Text("Web Gmail · sign in inside Inbox")
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
