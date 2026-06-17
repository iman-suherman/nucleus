import Foundation
import NucleusKit

enum DashboardQuotes {
    static let storageKey = "nucleus.dashboard.quote"

    private static let quotes: [String] = {
        guard let url = Bundle.main.url(forResource: "DashboardQuotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String].self, from: data),
              !decoded.isEmpty
        else {
            return [fallbackQuote]
        }
        return decoded
    }()

    private static let fallbackQuote = "May your day be calm, focused, and full of small wins."

    static func currentOrRandom() -> String {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           quotes.contains(saved) {
            return saved
        }
        return pickRandom()
    }

    static func pickRandom(excluding current: String? = nil) -> String {
        guard quotes.count > 1 else { return quotes.first ?? fallbackQuote }

        var candidate = quotes.randomElement() ?? fallbackQuote
        if let current, candidate == current {
            for _ in 0..<8 {
                let next = quotes.randomElement() ?? fallbackQuote
                if next != current {
                    candidate = next
                    break
                }
            }
        }

        UserDefaults.standard.set(candidate, forKey: storageKey)
        return candidate
    }

    static func quoteBody(from quote: String) -> String {
        var text = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        while text.hasSuffix(".") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    static func displayBody(from quote: String, emojis: String) -> String {
        let body = quoteBody(from: quote)
        let trimmedEmojis = emojis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmojis.isEmpty else { return body }
        return "\(body) \(trimmedEmojis) "
    }

    static func theme(for quote: String) -> String {
        let lower = quote.lowercased()

        if lower.contains("work") || lower.contains("focus") || lower.contains("effort")
            || lower.contains("momentum") || lower.contains("progress") {
            if lower.contains("heart") || lower.contains("kind") || lower.contains("gentle") {
                return "About letting meaningful work guide your priorities with warmth."
            }
            return "About meaningful work, focus, and steady progress."
        }

        if lower.contains("calm") || lower.contains("peace") || lower.contains("rest")
            || lower.contains("balance") || lower.contains("quiet") || lower.contains("breath") {
            return "About calm, balance, and making space to breathe."
        }

        if lower.contains("gratitude") || lower.contains("thank") || lower.contains("kindness")
            || lower.contains("generous") || lower.contains("warm") {
            return "About gratitude, kindness, and appreciating the day."
        }

        if lower.contains("hope") || lower.contains("dream") || lower.contains("grow")
            || lower.contains("bloom") || lower.contains("fresh") {
            return "About hope, growth, and welcoming what is ahead."
        }

        if lower.contains("clarity") || lower.contains("clear") || lower.contains("simple")
            || lower.contains("priority") || lower.contains("plan") {
            return "About clarity, simplicity, and knowing what matters."
        }

        if lower.contains("joy") || lower.contains("delight") || lower.contains("laugh")
            || lower.contains("light") || lower.contains("spark") {
            return "About joy, lightness, and small moments of delight."
        }

        if lower.contains("rain") || lower.contains("weather") || lower.contains("sun")
            || lower.contains("morning") || lower.contains("evening") {
            return "About moving through the day with ease and acceptance."
        }

        return "A gentle wish for a thoughtful, balanced day."
    }
}

enum DashboardDurationFormatting {
    static func analysisAgo(from date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes == 0 {
            return "just now"
        }
        if minutes == 1 {
            return "1 minute ago"
        }
        if minutes < 60 {
            return "\(minutes) minutes ago"
        }

        let hours = minutes / 60
        if hours == 1 {
            return "1 hour ago"
        }
        if hours < 24 {
            return "\(hours) hours ago"
        }

        let days = hours / 24
        if days == 1 {
            return "1 day ago"
        }
        return "\(days) days ago"
    }

    static func analysisUntil(_ date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 {
            return "due now"
        }
        if minutes == 1 {
            return "in 1 minute"
        }
        if minutes < 60 {
            return "in \(minutes) minutes"
        }

        let hours = Int(ceil(Double(minutes) / 60))
        if hours == 1 {
            return "in 1 hour"
        }
        return "in \(hours) hours"
    }
}

enum DashboardInsightFormatting {
    static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func insightParagraphs(from snapshot: DashboardSnapshot, asOf date: Date) -> [String] {
        var paragraphs = snapshot.activitySummary
        guard !paragraphs.isEmpty else {
            return ["As of \(formattedDate(date)) at \(formattedTime(date)), you have limited activity to report yet."]
        }

        paragraphs[0] = prefaceFirstParagraph(paragraphs[0], asOf: date)
        if !snapshot.productivitySummary.isEmpty {
            paragraphs.append(snapshot.productivitySummary)
        }
        return paragraphs
    }

    private static func prefaceFirstParagraph(_ paragraph: String, asOf date: Date) -> String {
        let preface = "As of \(formattedDate(date)) at \(formattedTime(date)), you have"
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("You have ") {
            let remainder = String(trimmed.dropFirst("You have ".count))
            return "\(preface) \(remainder)"
        }

        if trimmed.hasPrefix("Your inbox and chat are clear") {
            let remainder = trimmed.replacingOccurrences(of: "Your inbox and chat are clear", with: "a clear inbox and chat")
            return "\(preface) \(remainder)"
        }

        return "\(preface) \(trimmed.prefix(1).lowercased())\(trimmed.dropFirst())"
    }
}
