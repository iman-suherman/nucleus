import NucleusKit
import SwiftUI
import SyncKit

struct DashboardNucleusAIPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var cloudSyncService = NucleusCloudSyncService.shared
    @ObservedObject private var aiService = NucleusAIService.shared

    @State private var question = ""
    @State private var isConnecting = false
    @State private var connectMessage: String?

    var body: some View {
        dashboardActionBox(
            title: "Nucleus AI",
            systemImage: "sparkles",
            titleUsesGradient: true
        ) {
            if cloudSyncService.status.isConnected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [.purple.opacity(0.35), .orange.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Ask Nucleus AI…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitQuestion() }

                Button("Ask") {
                    submitQuestion()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiService.isLoading)
            }

            if aiService.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let answer = aiService.lastAnswer {
                Text(answer)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = aiService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Ask about your day, priorities, or anything Nucleus can help research.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to Nucleus Cloud to ask questions with live web research and AI overview.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(isConnecting ? "Opening Browser…" : "Connect Nucleus Cloud") {
                Task {
                    isConnecting = true
                    connectMessage = await viewModel.connectNucleusCloud()
                    isConnecting = false
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isConnecting)

            if let connectMessage {
                Text(connectMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func submitQuestion() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await aiService.ask(question: trimmed)
        }
    }
}

struct DashboardMusicPanel: View {
    @ObservedObject private var controller = MediaController.shared

    var body: some View {
        dashboardActionBox(
            title: "Apple Music",
            systemImage: "music.note"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if controller.playbackSource != .musicApp {
                    Button("Use Apple Music") {
                        controller.setPlaybackSource(.musicApp)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if controller.playbackSource == .musicApp, controller.musicAccess.needsSetup {
                    Button("Allow Apple Music Access") {
                        Task { await controller.setupMusicAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search songs…", text: $controller.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: controller.searchQuery) { _, _ in
                            controller.scheduleSearch()
                        }
                    if !controller.searchQuery.isEmpty {
                        Button {
                            controller.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if controller.catalogService.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !controller.searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(controller.searchResults.prefix(4).enumerated()), id: \.element.id) { index, result in
                            Button {
                                Task { await controller.playSearchResult(result) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: result.kind == .song ? "music.note" : "music.mic")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 14)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.title)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if controller.activeSearchResultID == result.id, controller.nowPlaying.isPlaying {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.teal)
                                    }
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < min(3, controller.searchResults.count - 1) {
                                Divider()
                            }
                        }
                    }
                }

                miniNowPlayingRow
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
        }
        .onAppear {
            controller.setPlaybackSource(.musicApp)
            controller.refreshMusicAccess()
            controller.refreshNowPlaying()
        }
    }

    @ViewBuilder
    private var miniNowPlayingRow: some View {
        let info = controller.nowPlaying
        if info.hasContent {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(info.artist.isEmpty ? "Now playing" : info.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    controller.togglePlayPause()
                } label: {
                    Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    controller.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

@ViewBuilder
private func dashboardActionBox<Content: View>(
    title: String,
    systemImage: String,
    titleUsesGradient: Bool = false,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
            if titleUsesGradient {
                Label {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .pink, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                } icon: {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.multicolor)
                }
            } else {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        content()
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
    }
    .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
}
