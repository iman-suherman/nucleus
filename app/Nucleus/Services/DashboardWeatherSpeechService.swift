import AVFoundation
import Foundation

@MainActor
final class DashboardWeatherSpeechService: NSObject, ObservableObject {
    static let shared = DashboardWeatherSpeechService()

    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(weather: DashboardTodayWeather, locationLabel: String?) {
        stop()

        let text = Self.spokenText(for: weather, locationLabel: locationLabel)
        let utterance = AVSpeechUtterance(string: text)
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

    static func spokenText(for weather: DashboardTodayWeather, locationLabel: String?) -> String {
        let location = weather.cityName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? locationLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "your location"

        var parts = [
            "Today's weather in \(location): \(weather.conditionDescription).",
            "High \(speakableTemperature(weather.highTemperature)), low \(speakableTemperature(weather.lowTemperature)).",
        ]

        if let rainSummary = weather.rainSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rainSummary.isEmpty {
            parts.append(rainSummary)
        }

        return parts.joined(separator: " ")
    }

    private static func speakableTemperature(_ value: String) -> String {
        value
            .replacingOccurrences(of: "°C", with: " degrees Celsius")
            .replacingOccurrences(of: "°F", with: " degrees Fahrenheit")
            .replacingOccurrences(of: "°", with: " degrees")
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

extension DashboardWeatherSpeechService: AVSpeechSynthesizerDelegate {
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
