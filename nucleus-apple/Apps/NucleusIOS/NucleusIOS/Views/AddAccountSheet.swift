import SwiftUI

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var displayName = ""

    let onSubmit: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Google account") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    TextField("Display name (optional)", text: $displayName)
                }

                Section {
                    Text("After adding the account, sign in through the Mail tab. Web sessions stay on this device — same as macOS Nucleus.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSubmit(email, displayName)
                        dismiss()
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
