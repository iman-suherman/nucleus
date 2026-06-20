import NucleusKit
import SwiftUI

struct KaraokeLyricsView: View {
    @ObservedObject var lyricsController: MusicLyricsController
    let nowPlaying: MediaNowPlayingInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Lyrics", systemImage: "text.quote")
                    .font(.headline)
                Spacer()
                if lyricsController.isSynced {
                    Text("Karaoke")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }

            if nowPlaying.hasContent {
                Text(nowPlaying.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(nowPlaying.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if !nowPlaying.hasContent {
            placeholder(
                title: "Nothing Playing",
                systemImage: "music.note",
                detail: "Play a song to see synced lyrics here."
            )
        } else if lyricsController.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading lyrics…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = lyricsController.statusMessage {
            placeholder(
                title: "No Lyrics",
                systemImage: "text.quote.rtl",
                detail: message
            )
        } else if lyricsController.isSynced {
            syncedLyricsScroll
        } else if !lyricsController.plainLines.isEmpty {
            plainLyricsScroll
        } else {
            placeholder(
                title: "No Lyrics",
                systemImage: "text.quote.rtl",
                detail: "Lyrics aren't available for this track."
            )
        }
    }

    private var syncedLyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(lyricsController.syncedLines) { line in
                        syncedLineView(line)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lyricsController.activeSyncedLineIndex) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onAppear {
                if let index = lyricsController.activeSyncedLineIndex {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func syncedLineView(_ line: SyncedLyricLine) -> some View {
        let isActive = lyricsController.activeSyncedLineIndex == line.id
        let progress = isActive ? lyricsController.lineProgress(for: line.id) : 0

        KaraokeLyricLineText(
            text: line.text,
            isActive: isActive,
            isPast: (lyricsController.activeSyncedLineIndex ?? -1) > line.id,
            fillProgress: progress
        )
    }

    private var plainLyricsScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(lyricsController.plainLines.enumerated()), id: \.offset) { index, line in
                    let isActive = lyricsController.activePlainLineIndex == index
                    KaraokeLyricLineText(
                        text: line,
                        isActive: isActive,
                        isPast: (lyricsController.activePlainLineIndex ?? -1) > index,
                        fillProgress: isActive ? 1 : 0
                    )
                    .id(index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func placeholder(title: String, systemImage: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

private struct KaraokeLyricLineText: View {
    let text: String
    let isActive: Bool
    let isPast: Bool
    let fillProgress: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(font)
                .fontWeight(isActive ? .bold : .regular)
                .foregroundStyle(baseColor)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isActive {
                Text(text)
                    .font(font)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: max(0, geo.size.width * fillProgress))
                        }
                    }
            }
        }
        .animation(.linear(duration: 0.05), value: fillProgress)
        .scaleEffect(isActive ? 1.04 : 1, anchor: .leading)
        .opacity(isPast ? 0.45 : (isActive ? 1 : 0.72))
        .animation(.easeInOut(duration: 0.25), value: isActive)
    }

    private var font: Font {
        isActive ? .title3 : .body
    }

    private var baseColor: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(.secondary)
        }
        if isPast {
            return AnyShapeStyle(.tertiary)
        }
        return AnyShapeStyle(.secondary)
    }
}
