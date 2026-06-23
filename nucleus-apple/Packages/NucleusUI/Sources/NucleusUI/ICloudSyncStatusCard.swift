import NucleusCore
import SwiftUI

public struct ICloudAccountDetailsView: View {
    let syncService: ICloudSyncDisplayService
    var onRefresh: (() -> Void)?

    public init(syncService: ICloudSyncDisplayService, onRefresh: (() -> Void)? = nil) {
        self.syncService = syncService
        self.onRefresh = onRefresh
    }

    public var body: some View {
        Group {
            if syncService.isSignedIn {
                if let name = syncService.accountName {
                    LabeledContent("Account") {
                        Text(name)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    LabeledContent("Account") {
                        Text("Signed in")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Notes sync through this account. Use the same account on your computer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sign in to cloud sync in device Settings to sync notes from your computer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let onRefresh {
                Button("Refresh account", action: onRefresh)
            }
        }
    }
}

public struct ICloudSyncStatusCard: View {
    let syncService: ICloudSyncDisplayService
    let notesService: NotesMetadataService
    let primaryNotesAccountEmail: String?
    var onRefresh: (() -> Void)?

    public init(
        syncService: ICloudSyncDisplayService,
        notesService: NotesMetadataService,
        primaryNotesAccountEmail: String?,
        onRefresh: (() -> Void)? = nil
    ) {
        self.syncService = syncService
        self.notesService = notesService
        self.primaryNotesAccountEmail = primaryNotesAccountEmail
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: syncService.isSyncAvailable ? "checkmark.icloud.fill" : "icloud.slash")
                    .foregroundStyle(syncService.isSyncAvailable ? .green : .secondary)
                Text(syncService.statusLabel)
                    .font(.subheadline.weight(.medium))
            }

            if let name = syncService.accountName {
                LabeledContent("Account") {
                    Text(name)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            LabeledContent("Notes storage") {
                Text(notesService.usesCloudKitSync ? "Private cloud sync" : "This device only")
                    .foregroundStyle(notesService.usesCloudKitSync ? Color.secondary : Color.orange)
                    .multilineTextAlignment(.trailing)
            }

            if !notesService.usesCloudKitSync {
                Text(notesService.syncStatusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Notes on this device") {
                Text("\(notesService.notes.count)")
                    .foregroundStyle(.secondary)
            }

            if let email = primaryNotesAccountEmail {
                LabeledContent("Google Drive backup") {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let lastChange = syncService.lastRemoteChangeAt {
                LabeledContent("Last cloud update") {
                    Text(lastChange, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            if let onRefresh {
                Button("Refresh notes from cloud", action: onRefresh)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

public struct NotesSyncFooter: View {
    let syncService: ICloudSyncDisplayService
    let notesService: NotesMetadataService

    public init(syncService: ICloudSyncDisplayService, notesService: NotesMetadataService) {
        self.syncService = syncService
        self.notesService = notesService
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: notesService.usesCloudKitSync ? "icloud.fill" : "icloud.slash")
                .font(.caption2)
            if notesService.usesCloudKitSync {
                Text("\(notesService.notes.count) notes · \(syncService.accountDisplayName)")
            } else {
                Text("\(notesService.notes.count) notes · not syncing from computer")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
