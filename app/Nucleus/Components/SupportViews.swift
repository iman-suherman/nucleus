import AppKit
import NucleusKit
import SwiftUI

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

    var body: some View {
        Form {
            Section("Mail") {
                Picker("Notification sound", selection: $settings.mailNotificationSound) {
                    ForEach(MailNotificationSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                Button("Play preview") {
                    previewMailNotificationSound(settings.mailNotificationSound)
                }
                .disabled(settings.mailNotificationSound == .silent)
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
        .padding(24)
    }
}

private func previewMailNotificationSound(_ sound: MailNotificationSound) {
    if let url = sound.previewBundleURL {
        NSSound(contentsOf: url, byReference: true)?.play()
        return
    }
    if sound == .system {
        NSSound.beep()
    }
}
