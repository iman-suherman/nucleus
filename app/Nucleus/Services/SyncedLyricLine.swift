import Foundation

struct SyncedLyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let start: TimeInterval
    let text: String
}

enum LRCParser {
    static func parse(_ raw: String) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        var index = 0

        for row in raw.components(separatedBy: .newlines) {
            let trimmed = row.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let timestamp = parseTimestampPrefix(from: trimmed) else { continue }
            let text = stripTimestampPrefix(from: trimmed).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            lines.append(SyncedLyricLine(id: index, start: timestamp, text: text))
            index += 1
        }

        return lines.sorted { $0.start < $1.start }
    }

    private static func parseTimestampPrefix(from line: String) -> TimeInterval? {
        guard line.first == "[" else { return nil }
        guard let close = line.firstIndex(of: "]") else { return nil }
        let stamp = line[line.index(after: line.startIndex)..<close]
        return parseTimestamp(String(stamp))
    }

    private static func stripTimestampPrefix(from line: String) -> String {
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return line }
        return String(line[line.index(after: close)...])
    }

    private static func parseTimestamp(_ stamp: String) -> TimeInterval? {
        let parts = stamp.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        guard let minutes = Double(parts[0]) else { return nil }
        let secondPart = parts[1].replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(secondPart) else { return nil }

        var total = minutes * 60 + seconds
        if parts.count >= 3, let fractional = Double(parts[2].replacingOccurrences(of: ",", with: ".")) {
            total += fractional / 100
        }
        return total
    }
}

enum SyncedLyricsIndex {
    static func activeLineIndex(at elapsed: TimeInterval, in lines: [SyncedLyricLine]) -> Int? {
        guard !lines.isEmpty else { return nil }

        var active = 0
        for (index, line) in lines.enumerated() where line.start <= elapsed {
            active = index
        }
        return active
    }

    static func lineProgress(
        at elapsed: TimeInterval,
        lineIndex: Int,
        lines: [SyncedLyricLine],
        trackDuration: TimeInterval
    ) -> Double {
        guard lines.indices.contains(lineIndex) else { return 0 }

        let start = lines[lineIndex].start
        let end: TimeInterval
        if lineIndex + 1 < lines.count {
            end = lines[lineIndex + 1].start
        } else if trackDuration > start {
            end = trackDuration
        } else {
            end = start + 4
        }

        guard end > start else { return 1 }
        return min(1, max(0, (elapsed - start) / (end - start)))
    }
}
