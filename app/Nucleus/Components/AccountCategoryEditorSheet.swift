import SwiftUI

struct AccountCategoryEditorSheet: View {
    let title: String
    let actionLabel: String
    @Binding var categoryName: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())

            TextField("Category name", text: $categoryName)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)

            Text("Examples: Personal, Work, Client, Freelance")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionLabel, action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { isFocused = true }
    }
}
