import AppKit
import SwiftUI

struct NucleusAppLogo: View {
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 7

    var body: some View {
        Group {
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "atom")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

enum NucleusBadgeKind {
    case mail
    case chat
    case neutral

    var foreground: Color {
        switch self {
        case .mail: .blue
        case .chat: Color(red: 129 / 255, green: 201 / 255, blue: 149 / 255)
        case .neutral: .primary
        }
    }

    var background: Color {
        switch self {
        case .mail: .blue.opacity(0.22)
        case .chat: Color(red: 129 / 255, green: 201 / 255, blue: 149 / 255).opacity(0.22)
        case .neutral: Color.secondary.opacity(0.2)
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
            .foregroundStyle(kind == .neutral ? kind.foreground : .white)
            .background(badgeBackground, in: Capsule())
    }

    private var badgeBackground: Color {
        switch kind {
        case .mail: .blue.opacity(0.85)
        case .chat: Color(red: 129 / 255, green: 201 / 255, blue: 149 / 255).opacity(0.9)
        case .neutral: kind.background
        }
    }
}

extension View {
    func nucleusAccountTab(isSelected: Bool) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
    }
}
