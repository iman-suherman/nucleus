import SwiftUI

struct ReleaseNotesDetailView: View {
    let release: AppReleaseNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(release.headline)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Version \(release.version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if release.sections.isEmpty {
                Text("This update includes improvements and fixes across mail, chat, calendar, notes, and sync.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(release.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.items, id: \.self) { item in
                                ReleaseNotesBulletRow(text: item)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReleaseNotesBulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
