import Foundation

public struct ClipboardPasswordAnalysis: Equatable, Sendable {
    public enum Confidence: Sendable {
        case high
        case medium
    }

    public var extractedPassword: String
    public var confidence: Confidence
    public var reason: String

    public init(extractedPassword: String, confidence: Confidence, reason: String) {
        self.extractedPassword = extractedPassword
        self.confidence = confidence
        self.reason = reason
    }
}

/// On-device clipboard analysis for password-like secrets.
public enum ClipboardPasswordAnalyzer {
    private static let passwordLabelPattern = #"(?i)(password|passwd|pass|pwd|secret|api[_-]?key|token)\s*[:=]\s*(.+)"#

    public static func analyze(_ content: String) -> ClipboardPasswordAnalysis? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let labeled = extractLabeledPassword(from: trimmed) {
            return labeled
        }

        let candidate = primaryCandidate(from: trimmed)
        guard isLikelyPasswordToken(candidate) else { return nil }

        let score = passwordScore(candidate)
        guard score >= 4 else { return nil }

        let confidence: ClipboardPasswordAnalysis.Confidence = score >= 6 ? .high : .medium
        return ClipboardPasswordAnalysis(
            extractedPassword: candidate,
            confidence: confidence,
            reason: reason(for: candidate, score: score)
        )
    }

    private static func extractLabeledPassword(from content: String) -> ClipboardPasswordAnalysis? {
        guard let regex = try? NSRegularExpression(pattern: passwordLabelPattern) else { return nil }

        for line in content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges > 2,
                  let valueRange = Range(match.range(at: 2), in: line) else { continue }

            let value = String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 256 else { continue }
            guard !isURL(value), !isEmail(value) else { continue }

            return ClipboardPasswordAnalysis(
                extractedPassword: value,
                confidence: .high,
                reason: "Labeled password field"
            )
        }

        return nil
    }

    private static func primaryCandidate(from content: String) -> String {
        if content.contains("\n") {
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if lines.count == 1 {
                return lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .max(by: { passwordScore($0) < passwordScore($1) }) ?? lines[0]
        }
        return content
    }

    private static func isLikelyPasswordToken(_ candidate: String) -> Bool {
        guard candidate.count >= 8, candidate.count <= 256 else { return false }
        guard !isURL(candidate), !isEmail(candidate) else { return false }
        guard !isUUID(candidate), !isJWT(candidate) else { return false }
        guard !looksLikePath(candidate), !looksLikeCommand(candidate) else { return false }
        guard !looksLikePlainSentence(candidate) else { return false }
        return true
    }

    private static func passwordScore(_ value: String) -> Int {
        var score = 0

        if value.count >= 12 { score += 1 }
        if value.count >= 16 { score += 1 }

        let hasLower = value.contains(where: \.isLowercase)
        let hasUpper = value.contains(where: \.isUppercase)
        let hasDigit = value.contains(where: \.isNumber)
        let hasSymbol = value.contains(where: { !$0.isLetter && !$0.isNumber })

        if hasLower { score += 1 }
        if hasUpper { score += 1 }
        if hasDigit { score += 1 }
        if hasSymbol { score += 2 }

        let categories = [hasLower, hasUpper, hasDigit, hasSymbol].filter { $0 }.count
        if categories >= 3 { score += 1 }

        if !value.contains(where: \.isWhitespace) { score += 1 }

        return score
    }

    private static func reason(for value: String, score: Int) -> String {
        if score >= 6 {
            return "Strong password pattern with mixed characters"
        }
        return "Password-like secret without spaces"
    }

    private static func isURL(_ value: String) -> Bool {
        value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("ftp://")
    }

    private static func isEmail(_ value: String) -> Bool {
        value.contains("@") && value.contains(".") && !value.contains(where: \.isWhitespace)
    }

    private static func isUUID(_ value: String) -> Bool {
        let pattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isJWT(_ value: String) -> Bool {
        value.hasPrefix("eyJ") && value.split(separator: ".").count == 3
    }

    private static func looksLikePath(_ value: String) -> Bool {
        value.hasPrefix("/") || value.hasPrefix("~/") || value.contains("\\")
    }

    private static func looksLikeCommand(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let prefixes = ["kubectl ", "docker ", "npm ", "yarn ", "pnpm ", "git ", "curl ", "wget "]
        return prefixes.contains(where: { lowered.hasPrefix($0) })
    }

    private static func looksLikePlainSentence(_ value: String) -> Bool {
        let words = value.split(whereSeparator: \.isWhitespace)
        guard words.count >= 4 else { return false }

        let letters = value.filter(\.isLetter)
        guard !letters.isEmpty else { return false }

        let uppercaseRatio = Double(letters.filter(\.isUppercase).count) / Double(letters.count)
        return uppercaseRatio < 0.15
    }
}
