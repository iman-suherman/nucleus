import AppKit
import NucleusKit
import SwiftUI
import SyncKit

private enum DashboardActionPanelMetrics {
    static let resultsAreaHeight: CGFloat = 108
    static let artworkSize: CGFloat = 36
}

struct DashboardNucleusAIPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var cloudSyncService = NucleusCloudSyncService.shared
    @ObservedObject private var aiService = NucleusAIService.shared
    @ObservedObject private var speechService = DashboardNewsSpeechService.shared
    @Binding var isExpanded: Bool

    @State private var question = ""
    @State private var isConnecting = false
    @State private var connectMessage: String?
    @State private var copyConfirmed = false

    init(isExpanded: Binding<Bool>) {
        _isExpanded = isExpanded
    }

    var body: some View {
        dashboardActionBox(
            title: "Nucleus AI",
            systemImage: "sparkles",
            titleUsesGradient: true,
            isExpanded: $isExpanded
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

            dashboardAISlowReadingScrollArea(scrollTrigger: aiService.lastAnswer) {
                if aiService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else if let answer = aiService.lastAnswer {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button {
                                copyAnswer(answer, question: question)
                            } label: {
                                Label(copyConfirmed ? "Copied" : "Copy", systemImage: copyConfirmed ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button {
                                toggleAnswerSpeech(answer)
                            } label: {
                                Label(
                                    speechService.isSpeaking ? "Stop" : "Speak",
                                    systemImage: speechService.isSpeaking ? "stop.fill" : "speaker.wave.2.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Spacer(minLength: 0)
                        }

                        Text(answer)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else if let error = aiService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Ask about your day, priorities, or anything Nucleus can help research.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        speechService.stop()
        copyConfirmed = false
        Task {
            await aiService.ask(question: trimmed)
        }
    }

    private func copyAnswer(_ text: String, question: String) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let downloadURL = AppSettings.marketingWebsiteURL.absoluteString
        var payload = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedQuestion.isEmpty {
            payload = "Question: \(trimmedQuestion)\n\n\(payload)"
        }

        payload += "\n\n— Nucleus AI\n\nWant the same experience? Download Nucleus from \(downloadURL)"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        copyConfirmed = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copyConfirmed = false
        }
    }

    private func toggleAnswerSpeech(_ text: String) {
        if speechService.isSpeaking {
            speechService.stop()
            return
        }
        speechService.speak(text: text)
    }
}

struct DashboardMusicPanel: View {
    @ObservedObject private var controller = MediaController.shared
    @Binding var isExpanded: Bool

    init(isExpanded: Binding<Bool>) {
        _isExpanded = isExpanded
    }

    var body: some View {
        dashboardActionBox(
            title: "Apple Music",
            systemImage: "music.note",
            isExpanded: $isExpanded
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

                dashboardMusicResultsScroll
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

    private var dashboardMusicResultsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if controller.catalogService.isSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if !controller.upcomingSearchResults.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(controller.upcomingSearchResults) { result in
                                musicSearchResultRow(result)
                                    .id(result.id)
                                if result.id != controller.upcomingSearchResults.last?.id {
                                    Divider()
                                        .padding(.leading, DashboardActionPanelMetrics.artworkSize + 8)
                                }
                            }
                        }
                    } else if controller.nowPlaying.hasContent {
                        dashboardNowPlayingContent
                    } else {
                        Text("Search Apple Music to play songs from your dashboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: DashboardActionPanelMetrics.resultsAreaHeight)
            .onChange(of: controller.activeSearchResultID) { _, activeID in
                scrollActiveTrackToTop(activeID, proxy: proxy)
            }
            .onChange(of: controller.upcomingSearchResults.map(\.id)) { _, _ in
                scrollActiveTrackToTop(controller.activeSearchResultID, proxy: proxy)
            }
            .onAppear {
                scrollActiveTrackToTop(controller.activeSearchResultID, proxy: proxy)
            }
        }
    }

    private func scrollActiveTrackToTop(_ activeID: String?, proxy: ScrollViewProxy) {
        guard let activeID else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(activeID, anchor: .top)
        }
    }

    private func musicSearchResultRow(_ result: MediaSearchResult) -> some View {
        let isActive = controller.activeSearchResultID == result.id

        return Button {
            Task { await controller.playSearchResult(result) }
        } label: {
            HStack(spacing: 8) {
                musicArtwork(
                    urlString: result.artworkURL,
                    systemImage: musicIcon(for: result.kind)
                )
                .frame(width: DashboardActionPanelMetrics.artworkSize, height: DashboardActionPanelMetrics.artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isActive, controller.nowPlaying.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dashboardNowPlayingContent: some View {
        let info = controller.nowPlaying

        return HStack(spacing: 10) {
            musicArtwork(urlString: info.artworkURL, systemImage: "music.note")
                .frame(width: DashboardActionPanelMetrics.artworkSize, height: DashboardActionPanelMetrics.artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func musicArtwork(urlString: String?, systemImage: String) -> some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    musicArtworkPlaceholder(systemImage: systemImage)
                default:
                    ZStack {
                        musicArtworkPlaceholder(systemImage: systemImage)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        } else {
            musicArtworkPlaceholder(systemImage: systemImage)
        }
    }

    private func musicArtworkPlaceholder(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func musicIcon(for kind: MediaSearchKind) -> String {
        switch kind {
        case .song: return "music.note"
        case .album: return "square.stack"
        case .artist: return "music.mic"
        case .playlist: return "music.note.list"
        }
    }
}

@ViewBuilder
private func dashboardAISlowReadingScrollArea<Content: View>(
    scrollTrigger: String?,
    @ViewBuilder content: @escaping () -> Content
) -> some View {
    DashboardAISlowReadingScrollArea(scrollTrigger: scrollTrigger, content: content)
}

private struct DashboardScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DashboardAISlowReadingScrollArea<Content: View>: View {
    let scrollTrigger: String?
    @ViewBuilder private let content: () -> Content

    init(scrollTrigger: String?, @ViewBuilder content: @escaping () -> Content) {
        self.scrollTrigger = scrollTrigger
        self.content = content
    }

    @State private var contentHeight: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>?
    @State private var pendingScrollAnswer: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("scroll-top")
                    content()
                    Color.clear.frame(height: 1).id("scroll-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: DashboardScrollContentHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
            }
            .frame(height: DashboardActionPanelMetrics.resultsAreaHeight)
            .onPreferenceChange(DashboardScrollContentHeightKey.self) { height in
                contentHeight = height
                scheduleSlowReadingScroll(proxy: proxy)
            }
            .onChange(of: scrollTrigger) { _, answer in
                pendingScrollAnswer = answer
                if answer == nil {
                    scrollTask?.cancel()
                    proxy.scrollTo("scroll-top", anchor: .top)
                    pendingScrollAnswer = nil
                    return
                }
                scheduleSlowReadingScroll(proxy: proxy)
            }
            .onDisappear {
                scrollTask?.cancel()
            }
        }
    }

    private func scheduleSlowReadingScroll(proxy: ScrollViewProxy) {
        guard let answer = pendingScrollAnswer else { return }
        beginSlowReadingScroll(answer: answer, proxy: proxy)
    }

    private func beginSlowReadingScroll(answer: String, proxy: ScrollViewProxy) {
        scrollTask?.cancel()

        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            proxy.scrollTo("scroll-top", anchor: .top)
            pendingScrollAnswer = nil
            return
        }

        scrollTask = Task {
            proxy.scrollTo("scroll-top", anchor: .top)
            try? await Task.sleep(for: .milliseconds(350))

            guard !Task.isCancelled else { return }

            let overflow = contentHeight - DashboardActionPanelMetrics.resultsAreaHeight
            pendingScrollAnswer = nil
            guard overflow > 8 else { return }

            try? await Task.sleep(for: .seconds(1.25))
            guard !Task.isCancelled else { return }

            let duration = min(24, max(8, Double(overflow) * 0.09))
            withAnimation(.linear(duration: duration)) {
                proxy.scrollTo("scroll-bottom", anchor: .bottom)
            }

            try? await Task.sleep(for: .seconds(duration + 0.5))
            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }

            withAnimation(.linear(duration: duration)) {
                proxy.scrollTo("scroll-top", anchor: .top)
            }
        }
    }
}

@ViewBuilder
private func dashboardResultsScrollArea<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
    ScrollView {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: DashboardActionPanelMetrics.resultsAreaHeight)
}

@ViewBuilder
private func dashboardActionBox<Content: View>(
    title: String,
    systemImage: String,
    titleUsesGradient: Bool = false,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        if isExpanded.wrappedValue {
            content()
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }
    .frame(maxWidth: .infinity, minHeight: isExpanded.wrappedValue ? 190 : nil, alignment: .topLeading)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
}
