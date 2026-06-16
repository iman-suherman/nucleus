import SwiftUI

/// Monochrome Nucleus mark for the menu bar: rounded N with the two orbital arcs from the app icon.
struct MenuBarNucleusMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let inset = size * 0.17
            let line = max(1.5, size * 0.105)
            let arc = Circle()
                .inset(by: inset)
                .stroke(style: StrokeStyle(lineWidth: line, lineCap: .round))

            ZStack {
                arc
                    .trim(from: 0.04, to: 0.24)
                arc
                    .trim(from: 0.54, to: 0.74)

                Text("N")
                    .font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .foregroundStyle(Color.primary)
        .accessibilityLabel("Nucleus")
    }
}
