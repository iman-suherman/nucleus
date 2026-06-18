import AppKit
import SwiftUI

struct DashboardNewsTickerView: View {
    let headlines: [DashboardNewsHeadline]
    let enrichments: [String: DashboardNewsEnrichment]
    let isLoading: Bool
    let statusMessage: String?
    var showsHeader: Bool = true
    var preferredContentHeight: CGFloat?

    @State private var visibleIndex = 0
    @State private var scrollTimer: Timer?

    private let rowHeight: CGFloat = 168
    private let visibleRows = 3
    private let advanceInterval: TimeInterval = 14
    private let cardVerticalPadding: CGFloat = 20

    private var viewportHeight: CGFloat {
        if let preferredContentHeight, preferredContentHeight > 0 {
            return max(preferredContentHeight - cardVerticalPadding, rowHeight)
        }
        return rowHeight * CGFloat(visibleRows)
    }

    private var effectiveVisibleRows: Int {
        if preferredContentHeight != nil {
            return max(1, Int(viewportHeight / rowHeight))
        }
        return visibleRows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                Label("News feed", systemImage: "newspaper.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
            }

            Group {
                if headlines.isEmpty, isLoading {
                    loadingCard
                } else if headlines.isEmpty, let statusMessage {
                    statusCard(statusMessage)
                } else if !headlines.isEmpty {
                    tickerCard
                } else {
                    statusCard("Headlines will appear here throughout the day.")
                }
            }
        }
        .onAppear { startScrollingIfNeeded() }
        .onDisappear { stopScrolling() }
        .onChange(of: headlines.count) { _, _ in
            visibleIndex = 0
            restartScrolling()
        }
        .onChange(of: preferredContentHeight) { _, _ in
            visibleIndex = 0
            restartScrolling()
        }
    }

    private var tickerCard: some View {
        let looped = loopedHeadlines
        let offset = CGFloat(visibleIndex) * rowHeight

        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(looped.enumerated()), id: \.offset) { _, headline in
                    headlineRow(headline)
                        .frame(height: rowHeight, alignment: .topLeading)
                }
            }
            .offset(y: -offset)
            .animation(.easeInOut(duration: 0.85), value: visibleIndex)
        }
        .frame(height: viewportHeight, alignment: .top)
        .clipped()
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: preferredContentHeight, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private var loopedHeadlines: [DashboardNewsHeadline] {
        guard !headlines.isEmpty else { return [] }
        return headlines + headlines.prefix(effectiveVisibleRows)
    }

    private func enrichment(for headline: DashboardNewsHeadline) -> DashboardNewsEnrichment {
        enrichments[headline.id]
            ?? DashboardNewsAnalysisService.fallbackEnrichment(for: headline)
    }

    private func headlineRow(_ headline: DashboardNewsHeadline) -> some View {
        let enrichment = enrichment(for: headline)
        let mood = enrichment.mood
        let displayTitle = DashboardNewsAnalysisService.cleanedTitle(headline.title)

        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(mood.accentColor)
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    moodBadge(mood)
                    Spacer(minLength: 0)
                    if let publishedAt = headline.publishedAt {
                        Text(relativeTime(from: publishedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                headlineTitleButton(displayTitle, link: headline.link)

                Text(enrichment.readerSummary)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(enrichment.moodExplanation)
                    .font(.caption2)
                    .foregroundStyle(mood.accentColor.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mood.backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(mood.accentColor.opacity(0.22), lineWidth: 1)
        }
        .padding(.vertical, 2)
    }

    private func moodBadge(_ mood: DashboardNewsMood) -> some View {
        Label(mood.label, systemImage: mood.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(mood.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(mood.accentColor.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func headlineTitleButton(_ title: String, link: URL?) -> some View {
        if let link {
            Button {
                ChromeLauncher.open(url: link)
            } label: {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        } else {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading headlines…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: preferredContentHeight, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusCard(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: preferredContentHeight, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private func relativeTime(from date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }

    private func startScrollingIfNeeded() {
        guard scrollTimer == nil, headlines.count > effectiveVisibleRows else { return }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: advanceInterval, repeats: true) { _ in
            Task { @MainActor in
                advanceTicker()
            }
        }
        if let scrollTimer {
            RunLoop.main.add(scrollTimer, forMode: .common)
        }
    }

    private func restartScrolling() {
        stopScrolling()
        startScrollingIfNeeded()
    }

    private func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func advanceTicker() {
        guard !headlines.isEmpty else { return }
        let maxIndex = headlines.count
        if visibleIndex >= maxIndex {
            visibleIndex = 0
        } else {
            visibleIndex += 1
        }
    }
}

private extension DashboardNewsMood {
    var accentColor: Color {
        switch self {
        case .uplifting:
            return Color(red: 0.18, green: 0.62, blue: 0.34)
        case .neutral:
            return Color(red: 0.36, green: 0.48, blue: 0.62)
        case .analytical:
            return Color(red: 0.24, green: 0.45, blue: 0.82)
        case .concerning:
            return Color(red: 0.86, green: 0.52, blue: 0.14)
        case .urgent:
            return Color(red: 0.84, green: 0.22, blue: 0.24)
        }
    }

    var backgroundColor: Color {
        accentColor.opacity(0.10)
    }

    var systemImage: String {
        switch self {
        case .uplifting: return "sun.max.fill"
        case .neutral: return "newspaper.fill"
        case .analytical: return "chart.bar.doc.horizontal.fill"
        case .concerning: return "exclamationmark.triangle.fill"
        case .urgent: return "bolt.fill"
        }
    }
}
