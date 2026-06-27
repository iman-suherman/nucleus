import NucleusKit
import SwiftUI

/// Flat sidebar + detail layout for reliable marketing screenshots (NavigationSplitView does not paint into cacheDisplay).
struct MarketingScreenshotLayout: View {
    let pane: WorkspacePane

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 248)
            Divider()
            MarketingWorkspacePreview(pane: pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            NucleusBrandMark(logoSize: 44, showText: true)
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 12)

            Text("Workspace")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            ForEach(WorkspacePane.primaryWorkspaces) { item in
                sidebarRow(for: item, selected: item == pane)
            }

            Spacer(minLength: 16)

            Text("System")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            ForEach(WorkspacePane.utilityWorkspaces) { item in
                sidebarRow(for: item, selected: false)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarRow(for item: WorkspacePane, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .frame(width: 20)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(selected ? .primary : .secondary)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            marketingBadge(for: item)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            selected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func marketingBadge(for item: WorkspacePane) -> some View {
        if MarketingScreenshotMode.showsMusicPlayingBadge, item == .media {
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
                .padding(4)
                .background(.green.opacity(0.15), in: Circle())
        } else if let badges = MarketingScreenshotMode.demoNoteBadges(for: item) {
            Text("\(badges.notes + badges.passwords)")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.25), in: Capsule())
        } else if let count = MarketingScreenshotMode.demoBadgeCount(for: item) {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(item == .inbox ? .white : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    item == .inbox ? Color.blue.opacity(0.85) : Color.secondary.opacity(0.25),
                    in: Capsule()
                )
        }
    }
}
