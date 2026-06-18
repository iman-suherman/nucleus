import AppKit
import SwiftUI

struct DashboardNewsTickerView: View {
    let headlines: [DashboardNewsHeadline]
    let isLoading: Bool
    let statusMessage: String?
    var showsHeader: Bool = true

    @State private var visibleIndex = 0
    @State private var scrollTimer: Timer?

    private let rowHeight: CGFloat = 112
    private let visibleRows = 4
    private let advanceInterval: TimeInterval = 12

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
        .frame(height: rowHeight * CGFloat(visibleRows), alignment: .top)
        .clipped()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private var loopedHeadlines: [DashboardNewsHeadline] {
        guard !headlines.isEmpty else { return [] }
        return headlines + headlines.prefix(visibleRows)
    }

    private func headlineRow(_ headline: DashboardNewsHeadline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            headlineTitleButton(headline)

            if !headline.summary.isEmpty {
                Text(headline.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let publishedAt = headline.publishedAt {
                Text(relativeTime(from: publishedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func headlineTitleButton(_ headline: DashboardNewsHeadline) -> some View {
        if let link = headline.link {
            Button {
                ChromeLauncher.open(url: link)
            } label: {
                Text(headline.title)
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
            Text(headline.title)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusCard(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        guard scrollTimer == nil, headlines.count > visibleRows else { return }
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
