import SwiftUI

public enum MobileBadgeKind: Sendable {
    case neutral
    case warning
    case urgent

    public var background: Color {
        switch self {
        case .neutral:
            Color.secondary.opacity(0.25)
        case .warning:
            Color(red: 1.0, green: 0.72, blue: 0.0)
        case .urgent:
            Color.red.opacity(0.9)
        }
    }

    public var foreground: Color {
        switch self {
        case .neutral:
            .primary
        case .warning, .urgent:
            .white
        }
    }
}

public struct MobileCountBadge: View {
    let count: Int
    var kind: MobileBadgeKind = .neutral

    public init(count: Int, kind: MobileBadgeKind = .neutral) {
        self.count = count
        self.kind = kind
    }

    public var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(kind.foreground)
            .background(kind.background, in: Capsule())
    }
}
