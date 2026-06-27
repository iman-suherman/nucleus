import SwiftUI

/// Horizontally scrolls long single-line dashboard copy when it does not fit.
public struct DashboardAutoScrollingText: View {
    private let text: String
    private let font: Font

    @ScaledMetric(relativeTo: .title3) private var lineHeight: CGFloat = 28
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>?

    private var overflow: CGFloat {
        max(0, textWidth - containerWidth)
    }

    private var shouldScroll: Bool {
        overflow > 4
    }

    public init(_ text: String, font: Font = .title3) {
        self.text = text
        self.font = font
    }

    public var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { textGeometry in
                        Color.clear.preference(
                            key: TextWidthPreferenceKey.self,
                            value: textGeometry.size.width
                        )
                    }
                }
                .offset(x: shouldScroll ? -offset : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .onPreferenceChange(TextWidthPreferenceKey.self) { textWidth = $0 }
                .onAppear {
                    containerWidth = geometry.size.width
                    restartScrollLoop()
                }
                .onChange(of: geometry.size.width) { _, width in
                    containerWidth = width
                    restartScrollLoop()
                }
        }
        .frame(height: lineHeight)
        .onChange(of: text) { _, _ in
            restartScrollLoop()
        }
        .onDisappear {
            scrollTask?.cancel()
        }
    }

    private func restartScrollLoop() {
        scrollTask?.cancel()
        offset = 0
        guard shouldScroll else { return }

        scrollTask = Task { @MainActor in
            let leadingPause: Duration = .seconds(2)
            let trailingPause: Duration = .seconds(1.5)
            let endGap: CGFloat = 24
            let scrollDuration = max(2.0, Double(overflow + endGap) / 28)

            while !Task.isCancelled {
                try? await Task.sleep(for: leadingPause)
                guard !Task.isCancelled, shouldScroll else { return }

                withAnimation(.linear(duration: scrollDuration)) {
                    offset = overflow + endGap
                }

                try? await Task.sleep(for: .seconds(scrollDuration) + trailingPause)
                guard !Task.isCancelled else { return }

                withAnimation(.easeOut(duration: 0.35)) {
                    offset = 0
                }
            }
        }
    }
}

private struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
