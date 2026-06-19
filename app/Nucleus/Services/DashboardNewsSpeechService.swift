import AVFoundation
import Foundation

@MainActor
final class DashboardNewsSpeechService: NSObject, ObservableObject {
    static let shared = DashboardNewsSpeechService()

    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(alert: DashboardBreakingNewsAlert) {
        speak(text: Self.spokenText(for: alert))
    }

    func speak(text: String) {
        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.05

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    static func spokenText(for alert: DashboardBreakingNewsAlert) -> String {
        [
            "Breaking news.",
            alert.displayTitle + ".",
            alert.enrichment.readerSummary,
        ]
        .joined(separator: " ")
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let locale = Locale.current
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let regionCode = locale.region?.identifier
        let preferredLanguage = regionCode.map { "\(languageCode)-\($0)" } ?? locale.identifier

        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let siriVoice = voices.first(where: { voice in
            voice.identifier.localizedCaseInsensitiveContains("siri")
                && voice.language.hasPrefix(languageCode)
        }) {
            return siriVoice
        }

        if let enhanced = voices.first(where: { voice in
            voice.language.hasPrefix(languageCode)
                && (voice.quality == .enhanced || voice.quality == .premium)
        }) {
            return enhanced
        }

        return AVSpeechSynthesisVoice(language: preferredLanguage)
            ?? AVSpeechSynthesisVoice(language: languageCode)
    }
}

extension DashboardNewsSpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
