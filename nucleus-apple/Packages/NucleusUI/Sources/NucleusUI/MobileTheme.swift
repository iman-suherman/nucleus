import NucleusCore
import SwiftUI

public enum NucleusMobileTheme {
    public static let accent = Color(red: 0.18, green: 0.45, blue: 0.95)
    public static let sidebarBackground = Color(.secondarySystemBackground)
    public static let workspaceBackground = Color(.systemBackground)
}

public struct AccountPickerMenu: View {
    let accounts: [GoogleAccount]
    let selectedAccountID: UUID?
    let onSelect: (GoogleAccount) -> Void

    public init(
        accounts: [GoogleAccount],
        selectedAccountID: UUID?,
        onSelect: @escaping (GoogleAccount) -> Void
    ) {
        self.accounts = accounts
        self.selectedAccountID = selectedAccountID
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    onSelect(account)
                } label: {
                    if account.id == selectedAccountID {
                        Label(account.email, systemImage: "checkmark")
                    } else {
                        Text(account.email)
                    }
                }
            }
        } label: {
            Label(selectedLabel, systemImage: "person.crop.circle")
                .font(.subheadline)
                .lineLimit(1)
        }
    }

    private var selectedLabel: String {
        if let selectedAccountID,
           let account = accounts.first(where: { $0.id == selectedAccountID }) {
            return account.displayName.isEmpty ? account.email : account.displayName
        }
        return accounts.first?.email ?? "Account"
    }
}

public struct EmptyAccountsPrompt: View {
    let onAddAccount: () -> Void

    public init(onAddAccount: @escaping () -> Void) {
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        ContentUnavailableView {
            Label("No Google accounts", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Add a Gmail account to open Mail, Calendar, and Chat in Nucleus.")
        } actions: {
            Button("Add account", action: onAddAccount)
                .buttonStyle(.borderedProminent)
        }
    }
}
