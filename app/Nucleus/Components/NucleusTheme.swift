import SwiftUI

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
