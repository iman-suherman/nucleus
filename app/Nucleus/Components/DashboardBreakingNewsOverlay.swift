import AppKit
import SwiftUI

struct DashboardBreakingNewsAlert: Identifiable, Equatable {
    let id: String
    let headline: DashboardNewsHeadline
    let enrichment: DashboardNewsEnrichment
    let displayTitle: String

    init(headline: DashboardNewsHeadline, enrichment: DashboardNewsEnrichment, displayTitle: String) {
        self.id = headline.id
        self.headline = headline
        self.enrichment = enrichment
        self.displayTitle = displayTitle
    }
}

enum BreakingNewsPresentationStore {
    private static let key = "nucleus.dashboard.seenBreakingNewsIDs"
    private static let maxStored = 200

    static func hasSeen(_ headlineID: String) -> Bool {
        seenIDs().contains(headlineID)
    }

    static func markSeen(_ headlineID: String) {
        var ids = seenIDs()
        ids.removeAll { $0 == headlineID }
        ids.insert(headlineID, at: 0)
        if ids.count > maxStored {
            ids = Array(ids.prefix(maxStored))
        }
        UserDefaults.standard.set(ids, forKey: key)
    }

    private static func seenIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}

struct DashboardBreakingNewsOverlay: View {
    private static let autoDismissSeconds = 20

    let alert: DashboardBreakingNewsAlert
    @ObservedObject var speechService: DashboardNewsSpeechService
    let onOpenLink: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var secondsRemaining = autoDismissSeconds
    @State private var autoDismissTask: Task<Void, Never>?

    private var accentColor: Color {
        Color(red: 0.84, green: 0.22, blue: 0.24)
    }

    var body: some View {
        Group {
            if isVisible {
                banner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear(perform: presentBanner)
        .onChange(of: alert.id) { _, _ in
            presentBanner()
        }
        .onDisappear(perform: cancelAutoDismissCountdown)
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Breaking news")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accentColor)

                        if !alert.headline.countryCode.isEmpty {
                            Text(DashboardPublicHolidayCountryCatalog.localizedCountryName(for: alert.headline.countryCode))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(alert.displayTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)

                Text("\(secondsRemaining)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.12), in: Circle())
                    .accessibilityLabel("Auto-closing in \(secondsRemaining) seconds")

                Button(action: dismissFromUserAction) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
                .pointerCursor()
            }

            Text(alert.enrichment.readerSummary)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)

            Text(alert.enrichment.moodExplanation)
                .font(.subheadline)
                .foregroundStyle(accentColor.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

            HStack(spacing: 10) {
                if alert.headline.link != nil {
                    Button(action: openLinkFromUserAction) {
                        Label("Open story", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .pointerCursor()
                }

                Button(action: toggleSpeech) {
                    Label(
                        speechService.isSpeaking ? "Stop" : "Speak",
                        systemImage: speechService.isSpeaking ? "stop.fill" : "speaker.wave.2.fill"
                    )
                }
                .buttonStyle(.bordered)
                .pointerCursor()

                Button("Close", action: dismissFromUserAction)
                    .buttonStyle(.bordered)
                    .pointerCursor()

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: 760, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.14),
                                    accentColor.opacity(0.28),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        }
    }

    private func presentBanner() {
        cancelAutoDismissCountdown()
        secondsRemaining = Self.autoDismissSeconds
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            isVisible = true
        }
        startAutoDismissCountdown()
    }

    private func dismissFromUserAction() {
        cancelAutoDismissCountdown()
        dismissAnimated(then: onDismiss)
    }

    private func openLinkFromUserAction() {
        cancelAutoDismissCountdown()
        dismissAnimated(then: onOpenLink)
    }

    private func toggleSpeech() {
        cancelAutoDismissCountdown()
        if speechService.isSpeaking {
            speechService.stop()
        } else {
            speechService.speak(alert: alert)
        }
    }

    private func dismissAnimated(then action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            isVisible = false
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            action()
        }
    }

    private func startAutoDismissCountdown() {
        autoDismissTask = Task { @MainActor in
            while secondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                secondsRemaining -= 1
            }
            guard !Task.isCancelled else { return }
            dismissAnimated(then: onDismiss)
        }
    }

    private func cancelAutoDismissCountdown() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }
}
