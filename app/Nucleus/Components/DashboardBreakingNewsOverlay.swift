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
    let alert: DashboardBreakingNewsAlert
    @ObservedObject var speechService: DashboardNewsSpeechService
    let onOpenLink: () -> Void
    let onDismiss: () -> Void

    private var accentColor: Color {
        Color(red: 0.84, green: 0.22, blue: 0.24)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()

            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(accentColor)
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Breaking news", systemImage: "newspaper.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(accentColor)

                        if !alert.headline.countryCode.isEmpty {
                            Text(DashboardPublicHolidayCountryCatalog.localizedCountryName(for: alert.headline.countryCode))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }

                Text(alert.displayTitle)
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(alert.enrichment.readerSummary)
                    .font(.title3)
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                Text(alert.enrichment.moodExplanation)
                    .font(.subheadline)
                    .foregroundStyle(accentColor.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Not now", action: onDismiss)
                        .buttonStyle(.bordered)

                    Button(action: toggleSpeech) {
                        Label(
                            speechService.isSpeaking ? "Stop" : "Speak",
                            systemImage: speechService.isSpeaking ? "stop.fill" : "speaker.wave.2.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if alert.headline.link != nil {
                        Button(action: onOpenLink) {
                            Label("Open story", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(26)
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(accentColor.opacity(0.45), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(125)
    }

    private func toggleSpeech() {
        if speechService.isSpeaking {
            speechService.stop()
        } else {
            speechService.speak(alert: alert)
        }
    }
}
