import Foundation

public enum NotesMarkdownHTML {
    public static func previewDocument(from markdown: String, colorScheme: String = "light") -> String {
        let body = htmlBody(from: NotesMarkdown.body(from: markdown))
        return wrapDocument(body: body, colorScheme: colorScheme)
    }

    public static func htmlBody(from markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let blocks = parseMarkdownBlocks(from: markdown)
        return blocks.map(renderMarkdownBlock).joined()
    }

    private static func wrapDocument(body: String, colorScheme: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en" data-color-scheme="\(escapeHTML(colorScheme))">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <style>
            :root {
              color-scheme: light dark;
              --text: #1d1d1f;
              --secondary: #6e6e73;
              --background: transparent;
              --code-bg: rgba(110, 118, 129, 0.12);
              --pre-bg: rgba(110, 118, 129, 0.08);
              --border: rgba(110, 118, 129, 0.28);
              --link: #0066cc;
              --quote-border: #c7c7cc;
            }
            html[data-color-scheme="dark"] {
              --text: #f5f5f7;
              --secondary: #a1a1a6;
              --code-bg: rgba(255, 255, 255, 0.08);
              --pre-bg: rgba(255, 255, 255, 0.06);
              --border: rgba(255, 255, 255, 0.14);
              --link: #409cff;
              --quote-border: #48484a;
            }
            @media (prefers-color-scheme: dark) {
              html:not([data-color-scheme="light"]) {
                --text: #f5f5f7;
                --secondary: #a1a1a6;
                --code-bg: rgba(255, 255, 255, 0.08);
                --pre-bg: rgba(255, 255, 255, 0.06);
                --border: rgba(255, 255, 255, 0.14);
                --link: #409cff;
                --quote-border: #48484a;
              }
            }
            * { box-sizing: border-box; }
            html, body {
              margin: 0;
              padding: 0;
              background: var(--background);
              color: var(--text);
              font: 15px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
              -webkit-font-smoothing: antialiased;
            }
            body { padding: 16px 18px 24px; }
            h1, h2, h3, h4, h5, h6 {
              line-height: 1.25;
              font-weight: 650;
              margin: 1.35em 0 0.55em;
              letter-spacing: -0.015em;
            }
            h1:first-child, h2:first-child, h3:first-child,
            h4:first-child, h5:first-child, h6:first-child,
            p:first-child, ul:first-child, ol:first-child,
            pre:first-child, blockquote:first-child { margin-top: 0; }
            h1 { font-size: 1.75em; }
            h2 { font-size: 1.45em; }
            h3 { font-size: 1.22em; }
            h4 { font-size: 1.08em; }
            h5 { font-size: 1em; color: var(--secondary); }
            h6 { font-size: 0.92em; color: var(--secondary); text-transform: uppercase; letter-spacing: 0.04em; }
            p { margin: 0 0 0.9em; }
            a { color: var(--link); text-decoration: none; }
            a:hover { text-decoration: underline; }
            strong { font-weight: 650; }
            em { font-style: italic; }
            del { opacity: 0.72; }
            code {
              font: 0.92em/1.4 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
              background: var(--code-bg);
              border-radius: 5px;
              padding: 0.12em 0.38em;
            }
            pre {
              margin: 0 0 1em;
              padding: 14px 16px;
              overflow-x: auto;
              background: var(--pre-bg);
              border: 1px solid var(--border);
              border-radius: 10px;
            }
            pre code {
              background: transparent;
              padding: 0;
              border-radius: 0;
              font-size: 0.88em;
              line-height: 1.5;
              white-space: pre-wrap;
              word-break: break-word;
            }
            ul, ol {
              margin: 0 0 0.95em;
              padding-left: 1.35em;
            }
            li { margin: 0.28em 0; }
            li > ul, li > ol { margin-bottom: 0.2em; }
            blockquote {
              margin: 0 0 1em;
              padding: 0.15em 0 0.15em 1em;
              border-left: 3px solid var(--quote-border);
              color: var(--secondary);
            }
            hr {
              border: 0;
              border-top: 1px solid var(--border);
              margin: 1.4em 0;
            }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case paragraph(String)
        case code(String, language: String?)
        case unorderedList([String])
        case orderedList([String])
        case blockquote([String])
        case horizontalRule
    }

    private static func parseMarkdownBlocks(from markdown: String) -> [MarkdownBlock] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(MarkdownBlock.code(codeLines.joined(separator: "\n"), language: language.isEmpty ? nil : language))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(MarkdownBlock.horizontalRule)
                index += 1
                continue
            }

            if let level = headingLevel(for: trimmed) {
                blocks.append(MarkdownBlock.heading(
                    level: level,
                    text: String(trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces))
                ))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    let content = current.dropFirst().trimmingCharacters(in: .whitespaces)
                    quoteLines.append(String(content))
                    index += 1
                }
                blocks.append(MarkdownBlock.blockquote(quoteLines))
                continue
            }

            if isUnorderedListLine(trimmed) {
                var items: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isUnorderedListLine(current), let item = unorderedListItem(from: current) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock.unorderedList(items))
                continue
            }

            if isOrderedListLine(trimmed) {
                var items: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isOrderedListLine(current), let item = orderedListItem(from: current) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock.orderedList(items))
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                let current = lines[index]
                let currentTrimmed = current.trimmingCharacters(in: .whitespaces)
                if currentTrimmed.isEmpty { break }
                if currentTrimmed.hasPrefix("```") { break }
                if headingLevel(for: currentTrimmed) != nil { break }
                if currentTrimmed.hasPrefix(">") { break }
                if isUnorderedListLine(currentTrimmed) || isOrderedListLine(currentTrimmed) { break }
                if currentTrimmed == "---" || currentTrimmed == "***" || currentTrimmed == "___" { break }
                paragraphLines.append(currentTrimmed)
                index += 1
            }
            blocks.append(MarkdownBlock.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func renderMarkdownBlock(_ block: MarkdownBlock) -> String {
        switch block {
        case let .heading(level, text):
            return "<h\(level)>\(inlineHTML(text))</h\(level)>"
        case let .paragraph(text):
            return "<p>\(inlineHTML(text))</p>"
        case let .code(text, _):
            return "<pre><code>\(escapeHTML(text))</code></pre>"
        case let .unorderedList(items):
            let rendered = items.map { "<li>\(inlineHTML($0))</li>" }.joined()
            return "<ul>\(rendered)</ul>"
        case let .orderedList(items):
            let rendered = items.map { "<li>\(inlineHTML($0))</li>" }.joined()
            return "<ol>\(rendered)</ol>"
        case let .blockquote(lines):
            let rendered = lines.map { "<p>\(inlineHTML($0))</p>" }.joined()
            return "<blockquote>\(rendered)</blockquote>"
        case .horizontalRule:
            return "<hr>"
        }
    }

    private static func headingLevel(for line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let remainder = line.dropFirst(hashes)
        guard remainder.first == " " || remainder.isEmpty else { return nil }
        return hashes
    }

    private static func isUnorderedListLine(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return (first == "-" || first == "*" || first == "+") && line.dropFirst().first == " "
    }

    private static func unorderedListItem(from line: String) -> String? {
        guard isUnorderedListLine(line) else { return nil }
        return String(line.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }

    private static func isOrderedListLine(_ line: String) -> Bool {
        guard let dotIndex = line.firstIndex(of: ".") else { return false }
        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return false }
        let afterDot = line.index(after: dotIndex)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return false }
        return true
    }

    private static func orderedListItem(from line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let afterDot = line.index(after: dotIndex)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...].trimmingCharacters(in: .whitespaces))
    }

    private static func inlineHTML(_ text: String) -> String {
        var tokens: [InlineToken] = [.text(text)]

        tokens = extractInline(tokens, pattern: #/`([^`]+)`/#) { .code($0) }
        tokens = extractInlineLink(tokens)
        tokens = extractInline(tokens, pattern: #/\*\*([^*]+)\*\*/#) { .strong($0) }
        tokens = extractInline(tokens, pattern: #/__([^_]+)__/#) { .strong($0) }
        tokens = extractInline(tokens, pattern: #/\*([^*]+)\*/#) { .emphasis($0) }
        tokens = extractInline(tokens, pattern: #/_([^_]+)_/#) { .emphasis($0) }
        tokens = extractInline(tokens, pattern: #/~~([^~]+)~~/#) { .strike($0) }

        return tokens.map(renderInlineToken).joined()
    }

    private enum InlineToken {
        case text(String)
        case code(String)
        case link(label: String, url: String)
        case strong(String)
        case emphasis(String)
        case strike(String)

        var textValue: String? {
            if case let .text(value) = self { return value }
            return nil
        }
    }

    private static func extractInline(
        _ tokens: [InlineToken],
        pattern: Regex<(Substring, Substring)>,
        transform: (String) -> InlineToken
    ) -> [InlineToken] {
        var output: [InlineToken] = []

        for token in tokens {
            guard let text = token.textValue else {
                output.append(token)
                continue
            }

            var remaining = text[...]
            while let match = remaining.firstMatch(of: pattern) {
                let before = remaining[..<match.range.lowerBound]
                if !before.isEmpty {
                    output.append(.text(String(before)))
                }
                output.append(transform(String(match.output.1)))
                remaining = remaining[match.range.upperBound...]
            }
            if !remaining.isEmpty {
                output.append(.text(String(remaining)))
            }
        }

        return output
    }

    private static func extractInlineLink(_ tokens: [InlineToken]) -> [InlineToken] {
        let pattern = #/\[([^\]]+)\]\(([^)]+)\)/#
        var output: [InlineToken] = []

        for token in tokens {
            guard let text = token.textValue else {
                output.append(token)
                continue
            }

            var remaining = text[...]
            while let match = remaining.firstMatch(of: pattern) {
                let before = remaining[..<match.range.lowerBound]
                if !before.isEmpty {
                    output.append(.text(String(before)))
                }
                output.append(.link(label: String(match.output.1), url: String(match.output.2)))
                remaining = remaining[match.range.upperBound...]
            }
            if !remaining.isEmpty {
                output.append(.text(String(remaining)))
            }
        }

        return output
    }

    private static func renderInlineToken(_ token: InlineToken) -> String {
        switch token {
        case let .text(value):
            return escapeHTML(value)
        case let .code(value):
            return "<code>\(escapeHTML(value))</code>"
        case let .link(label, url):
            return #"<a href="\#(escapeHTML(url))" rel="noopener noreferrer">\#(renderInlineChildren(label))</a>"#
        case let .strong(value):
            return "<strong>\(renderInlineChildren(value))</strong>"
        case let .emphasis(value):
            return "<em>\(renderInlineChildren(value))</em>"
        case let .strike(value):
            return "<del>\(renderInlineChildren(value))</del>"
        }
    }

    private static func renderInlineChildren(_ text: String) -> String {
        escapeHTML(text)
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
