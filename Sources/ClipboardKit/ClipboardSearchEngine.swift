import Foundation
import NaturalLanguage
import NucleusKit

struct SearchableClipboardEntry: Sendable {
    let entry: ClipboardEntry
    let normalizedContent: String
    let normalizedSource: String
    let normalizedTags: String
    let semanticSnippet: String

    init(entry: ClipboardEntry) {
        self.entry = entry
        normalizedContent = entry.content.lowercased()
        normalizedSource = entry.sourceApplication.lowercased()
        normalizedTags = entry.tags.joined(separator: " ").lowercased()
        semanticSnippet = String(entry.content.prefix(512))
    }
}

public actor ClipboardSearchEngine {
    public static let shared = ClipboardSearchEngine()

    private var indexed: [SearchableClipboardEntry] = []
    private var sentenceEmbedding: NLEmbedding?

    public init() {}

    public func rebuild(from entries: [ClipboardEntry]) {
        indexed = entries.map(SearchableClipboardEntry.init)
    }

    public func upsert(_ entry: ClipboardEntry) {
        if let index = indexed.firstIndex(where: { $0.entry.id == entry.id }) {
            indexed[index] = SearchableClipboardEntry(entry: entry)
        } else {
            indexed.insert(SearchableClipboardEntry(entry: entry), at: 0)
        }
    }

    public func rank(query: String) -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return indexed.map(\.entry)
        }

        let lowered = trimmed.lowercased()
        let tokens = lowered
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        let useSemantic = tokens.count >= 2 || lowered.count >= 4
        let embedding = useSemantic ? resolvedSentenceEmbedding() : nil

        var scored: [(ClipboardEntry, Int)] = []
        scored.reserveCapacity(indexed.count)

        for item in indexed {
            var score = lexicalScore(item, query: lowered, tokens: tokens)
            if let embedding {
                score = applySemanticBoost(
                    score: score,
                    query: trimmed,
                    item: item,
                    embedding: embedding
                )
            }
            if score > 0 {
                scored.append((item.entry, score))
            }
        }

        if scored.isEmpty, let embedding {
            for item in indexed {
                let distance = embedding.distance(between: trimmed, and: item.semanticSnippet)
                if distance < 0.75 {
                    let score = Int((1.0 - min(distance, 1.0)) * 60)
                    scored.append((item.entry, score))
                }
            }
        }

        guard !scored.isEmpty else { return [] }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.capturedAt > rhs.0.capturedAt
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private func resolvedSentenceEmbedding() -> NLEmbedding? {
        if sentenceEmbedding == nil {
            sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        }
        return sentenceEmbedding
    }

    private func lexicalScore(
        _ item: SearchableClipboardEntry,
        query: String,
        tokens: [String]
    ) -> Int {
        var score = 0

        if item.normalizedContent.contains(query) {
            score += 100
        } else if !tokens.isEmpty, tokens.allSatisfy({ item.normalizedContent.contains($0) }) {
            score += 80
        } else if tokens.contains(where: { item.normalizedContent.contains($0) }) {
            score += 40
        }

        if item.normalizedTags.contains(query) {
            score += 50
        } else if tokens.contains(where: { item.normalizedTags.contains($0) }) {
            score += 25
        }

        if item.normalizedSource.contains(query) {
            score += 25
        } else if tokens.contains(where: { item.normalizedSource.contains($0) }) {
            score += 15
        }

        if item.entry.isPinned {
            score += 10
        }

        return score
    }

    private func applySemanticBoost(
        score: Int,
        query: String,
        item: SearchableClipboardEntry,
        embedding: NLEmbedding
    ) -> Int {
        let distance = embedding.distance(between: query, and: item.semanticSnippet)
        guard distance < 0.85 else { return score }

        let semanticScore = Int((1.0 - min(distance, 1.0)) * 40)
        if score == 0 {
            return semanticScore
        }
        if distance < 0.5 {
            return score + 15
        }
        return score
    }
}
