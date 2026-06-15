import AppKit
import SwiftUI
import WebKit

enum NucleusTheme {
    /// Gmail dark theme canvas (#202124).
    static let canvas = Color(red: 32 / 255, green: 33 / 255, blue: 36 / 255)
    /// Slightly elevated panels and tabs (#292a2d).
    static let surface = Color(red: 41 / 255, green: 42 / 255, blue: 45 / 255)
    /// Search bars, chips, and hover states (#303134).
    static let elevated = Color(red: 48 / 255, green: 49 / 255, blue: 52 / 255)
    /// Selected sidebar rows and active tabs (#3c4043).
    static let selected = Color(red: 60 / 255, green: 64 / 255, blue: 67 / 255)
    /// Gmail primary text (#e8eaed).
    static let textPrimary = Color(red: 232 / 255, green: 234 / 255, blue: 237 / 255)
    /// Gmail secondary text (#9aa0a6).
    static let textSecondary = Color(red: 154 / 255, green: 160 / 255, blue: 166 / 255)
    /// Gmail accent blue (#8ab4f8) — mail unread badges.
    static let accent = Color(red: 138 / 255, green: 180 / 255, blue: 248 / 255)
    static let mailBadge = accent
    /// Google Chat green (#81c995) — chat unread badges.
    static let chatBadge = Color(red: 129 / 255, green: 201 / 255, blue: 149 / 255)
    /// Subtle separators (#3c4043).
    static let divider = Color(red: 60 / 255, green: 64 / 255, blue: 67 / 255)

    static var nsCanvas: NSColor {
        NSColor(red: 32 / 255, green: 33 / 255, blue: 36 / 255, alpha: 1)
    }

    static func applyWebViewChrome(to webView: WKWebView) {
        webView.setValue(nsCanvas, forKey: "underPageBackgroundColor")
        webView.enclosingScrollView?.drawsBackground = false
        webView.wantsLayer = true
        webView.layer?.backgroundColor = nsCanvas.cgColor
    }
}

extension View {
    func nucleusCanvasBackground() -> some View {
        background(NucleusTheme.canvas)
    }

    func nucleusSidebarListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(NucleusTheme.canvas)
    }

    func nucleusAccountTab(isSelected: Bool) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? NucleusTheme.selected : NucleusTheme.surface, in: Capsule())
            .foregroundStyle(isSelected ? NucleusTheme.textPrimary : NucleusTheme.textSecondary)
    }

    func nucleusWorkspaceChrome() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NucleusTheme.canvas)
    }
}

enum NucleusBadgeKind {
    case mail
    case chat
    case neutral

    var foreground: Color {
        switch self {
        case .mail: NucleusTheme.mailBadge
        case .chat: NucleusTheme.chatBadge
        case .neutral: NucleusTheme.textPrimary
        }
    }

    var background: Color {
        switch self {
        case .mail: NucleusTheme.mailBadge.opacity(0.25)
        case .chat: NucleusTheme.chatBadge.opacity(0.25)
        case .neutral: NucleusTheme.elevated
        }
    }
}

struct NucleusCountBadge: View {
    let count: Int
    var kind: NucleusBadgeKind = .neutral

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(kind.foreground)
            .background(kind.background, in: Capsule())
    }
}
