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

struct NucleusBrandMark: View {
    var logoSize: CGFloat = 36
    var cornerRadius: CGFloat?
    var showText: Bool = true

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? max(8, logoSize * 0.25)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            NucleusAppLogo(size: logoSize, cornerRadius: resolvedCornerRadius)

            if showText {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Nucleus")
                            .font(.title2.bold())
                        Text("(v.\(AppSettings.currentAppVersion))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Personal Operating System")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nucleus version \(AppSettings.currentAppVersion), Personal Operating System")
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

    func pointerCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
