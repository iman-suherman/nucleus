import SwiftUI

struct AddWebGmailAccountSheet: View {
    @Binding var email: String
    @Binding var categoryName: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case category
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCategory: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        trimmedEmail.contains("@") && !trimmedCategory.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Gmail (Web Sign-In)")
                .font(.title3.bold())

            Text("Use this for work or school Google accounts that block third-party apps. Sign in with your password or passkey when Google prompts you.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Gmail address", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .focused($focusedField, equals: .email)

            TextField("Category name", text: $categoryName)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .category)

            Text("Examples: Work, Client, Personal")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue to Gmail", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { focusedField = .email }
    }
}
