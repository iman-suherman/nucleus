import AppKit
import Charts
import DatabaseKit
import NucleusKit
import SwiftUI
import SyncKit

struct DashboardWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var syncService = CloudKitSyncService.shared
    @ObservedObject private var cloudSyncService = NucleusCloudSyncService.shared
    @ObservedObject private var weatherService = DashboardWeatherService.shared
    @ObservedObject private var processMetricsService = DashboardProcessMetricsService.shared

    @State private var isConnectingNucleusCloud = false
    @State private var nucleusCloudMessage: String?

    private var snapshot: DashboardSnapshot {
        viewModel.dashboardSnapshot()
    }

    private var billPaymentSummary: DashboardBillPaymentSummary {
        DashboardInsightsEngine.billPaymentSummary(
            bills: viewModel.activeBills,
            payments: viewModel.billPayments
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    metricsAndBillsRow
                    productivitySection
                }
                .padding(28)
                .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            weatherService.beginWeatherAccessFlow()
            processMetricsService.startSamplingIfNeeded()
            Task { await syncService.refreshAccountStatus() }
        }
        .onDisappear {
            processMetricsService.stopSampling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            weatherService.refreshIfNeeded()
        }
        .alert("Show today's weather?", isPresented: $weatherService.showLocationPermissionPrompt) {
            Button("Allow Location Access") {
                weatherService.confirmLocationPermissionRequest()
            }
            Button("Not Now", role: .cancel) {
                weatherService.declineLocationPermission()
            }
        } message: {
            Text("Nucleus uses your location to show today's forecast on the Dashboard. You can enable this later in System Settings.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            greetingWithQuote
            intelligentInsightSection

            if weatherService.isWeatherSectionVisible {
                weatherResourceAndSidebarRow
            } else {
                resourceAndSidebarRow
            }
        }
    }

    private var greetingWithQuote: some View {
        Text(greetingWithQuoteText)
            .font(.largeTitle.bold())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var greetingWithQuoteText: String {
        let quote = sanitizedDashboardQuote
        let greeting = "\(DashboardGreeting.timeOfDay()), \(DashboardGreeting.firstName)!"
        guard !quote.isEmpty else { return greeting }
        return "\(greeting) \(quote)"
    }

    private var sanitizedDashboardQuote: String {
        viewModel.dashboardQuote
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private var intelligentInsightSection: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let paragraphs = DashboardInsightFormatting.insightParagraphs(from: snapshot, asOf: context.date)

            VStack(alignment: .leading, spacing: 12) {
                Label("Intelligent insight", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        Text(paragraph)
                            .font(index == 0 ? .body.weight(.semibold) : .body)
                            .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.12),
                            Color.purple.opacity(0.10),
                            Color.pink.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.orange.opacity(0.45), .pink.opacity(0.35), .purple.opacity(0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            }
        }
    }

    private var weatherResourceAndSidebarRow: some View {
        HStack(alignment: .top, spacing: 16) {
            weatherForecastSection
                .frame(maxWidth: .infinity, alignment: .leading)

            ResourceUsageSummaryCard(metrics: processMetricsService.metrics)
                .frame(width: 200, alignment: .leading)

            sidebarPanel
        }
    }

    private var resourceAndSidebarRow: some View {
        HStack(alignment: .top, spacing: 16) {
            ResourceUsageSummaryCard(metrics: processMetricsService.metrics)
                .frame(width: 200, alignment: .leading)

            sidebarPanel

            Spacer(minLength: 0)
        }
    }

    private var sidebarPanel: some View {
        headerCloudSyncPanel
            .frame(width: 280, alignment: .topLeading)
    }

    @ViewBuilder
    private var weatherForecastSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let weather = weatherService.weather, let cityName = weather.cityName {
                Label("Today's weather · \(cityName)", systemImage: "cloud.sun.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
            } else {
                Label("Today's weather", systemImage: "cloud.sun.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
            }

            if let weather = weatherService.weather {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: weather.conditionSymbol)
                        .font(.system(size: 32))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(weather.conditionDescription)
                            .font(.title3.weight(.semibold))
                        Text("High \(weather.highTemperature) · Low \(weather.lowTemperature)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let rainSummary = weather.rainSummary {
                            Text(rainSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            } else if let statusMessage = weatherService.statusMessage {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: weatherService.isLoading ? "location" : "cloud.slash")
                        .foregroundStyle(.secondary)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !weatherService.isLoading {
                        Button("Try Again") {
                            weatherService.retryWeatherFetch()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            } else if weatherService.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading today's forecast…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "cloud.slash")
                        .foregroundStyle(.secondary)
                    Text("Weather is unavailable right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Try Again") {
                        weatherService.retryWeatherFetch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var metricsAndBillsRow: some View {
        HStack(alignment: .top, spacing: 20) {
            summaryAndResourceCards
                .frame(maxWidth: .infinity, alignment: .leading)

            upcomingBillsSection
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryAndResourceCards: some View {
        DashboardMetricsSummaryBox(
            unreadMailCount: snapshot.unreadMailCount,
            unreadChatCount: snapshot.unreadChatCount,
            passwordCount: snapshot.passwordCount,
            upcomingBillsCount: snapshot.upcomingBills.count,
            onUnreadEmail: { viewModel.sidebarSelection = .workspace(.inbox) },
            onUnreadChat: { viewModel.sidebarSelection = .workspace(.chat) },
            onPasswords: { viewModel.sidebarSelection = .workspace(.notes) },
            onBills: { viewModel.sidebarSelection = .workspace(.bills) }
        )
    }

    private var headerCloudSyncPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cloud sync", systemImage: "icloud")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                cloudSyncRow(
                    title: "Nucleus Cloud",
                    systemImage: "cloud",
                    isConnected: cloudSyncService.status.isConnected,
                    statusLabel: cloudSyncService.status.label,
                    connectTitle: isConnectingNucleusCloud ? "Opening Browser…" : "Connect",
                    isConnectDisabled: isConnectingNucleusCloud,
                    compact: true,
                    onConnect: {
                        isConnectingNucleusCloud = true
                        nucleusCloudMessage = "Authorize this Mac in your browser…"
                        Task {
                            nucleusCloudMessage = await viewModel.connectNucleusCloud()
                            isConnectingNucleusCloud = false
                        }
                    }
                )

                Divider()

                cloudSyncRow(
                    title: "iCloud",
                    systemImage: "icloud.fill",
                    isConnected: iCloudIsConnected,
                    statusLabel: iCloudStatusLabel,
                    connectTitle: iCloudConnectTitle,
                    isConnectDisabled: false,
                    compact: true,
                    onConnect: connectICloud
                )
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))

            if let nucleusCloudMessage {
                Text(nucleusCloudMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var iCloudIsConnected: Bool {
        syncService.status.isAvailable && NucleusDatabase.usesCloudKitSync
    }

    private var iCloudStatusLabel: String {
        if syncService.status.isAvailable, NucleusDatabase.usesCloudKitSync {
            return syncService.status.label
        }
        if !NucleusDatabase.usesCloudKitSync,
           let error = NucleusDatabase.lastCloudKitSetupError,
           !error.isEmpty {
            return error
        }
        return syncService.status.label
    }

    private var iCloudConnectTitle: String {
        if case .noAccount = syncService.status {
            return "Sign in to iCloud"
        }
        return "Open Settings"
    }

    private func connectICloud() {
        if case .noAccount = syncService.status {
            viewModel.openSystemICloudSettings()
            return
        }
        viewModel.openSettings(tab: .iCloud)
        Task { await syncService.refreshAccountStatus() }
    }

    private func cloudSyncRow(
        title: String,
        systemImage: String,
        isConnected: Bool,
        statusLabel: String,
        connectTitle: String,
        isConnectDisabled: Bool,
        compact: Bool = false,
        onConnect: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: compact ? 8 : 12) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : systemImage)
                .foregroundStyle(isConnected ? .green : .secondary)
                .font(compact ? .caption : .body)
                .frame(width: compact ? 16 : 22)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(title)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                Text(statusLabel)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if !isConnected {
                Button(connectTitle, action: onConnect)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isConnectDisabled)
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 8 : 12)
    }

    @ViewBuilder
    private var upcomingBillsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Payment preparation", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Spacer()
                Button("Open Bills") {
                    viewModel.sidebarSelection = .workspace(.bills)
                }
            }

            if billPaymentSummary.groups.isEmpty {
                Text("Nothing to prepare in the next two weeks.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            } else {
                billPaymentPreparationCard
            }
        }
    }

    private var billPaymentPreparationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(billPaymentSummary.groups) { group in
                HStack(spacing: 12) {
                    Image(systemName: group.category.systemImage)
                        .foregroundStyle(.purple)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(group.category.label) · \(group.currencyCode)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(group.billCount == 1 ? "1 bill" : "\(group.billCount) bills") due \(dueWindowLabel(for: group))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(NucleusFormatters.currencyString(group.totalAmount, currencyCode: group.currencyCode))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if group.id != billPaymentSummary.groups.last?.id {
                    Divider()
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.08),
                    Color.orange.opacity(0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [.purple.opacity(0.25), .orange.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func dueWindowLabel(for group: DashboardBillPaymentSummaryGroup) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: group.earliestDueDate)
        let end = calendar.startOfDay(for: group.latestDueDate)
        if start == end {
            return NucleusFormatters.dayHeader.string(from: group.earliestDueDate)
        }
        return "\(NucleusFormatters.dayHeader.string(from: group.earliestDueDate))–\(NucleusFormatters.dayHeader.string(from: group.latestDueDate))"
    }

    private var productivitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Productivity", systemImage: "chart.bar.fill")
                .font(.headline)

            Text("How your recent clipboard captures break down over the last 7 days.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshot.productivityBuckets.allSatisfy({ $0.count == 0 }) {
                ContentUnavailableView(
                    "No clipboard activity yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy something from another app to build your productivity profile.")
                )
                .frame(height: 220)
            } else {
                Chart(snapshot.productivityBuckets) { bucket in
                    BarMark(
                        x: .value("Category", bucket.category.rawValue),
                        y: .value("Captures", bucket.count)
                    )
                    .foregroundStyle(by: .value("Category", bucket.category.rawValue))
                    .cornerRadius(6)
                }
                .chartForegroundStyleScale([
                    ClipboardProductivityCategory.development.rawValue: Color.blue,
                    ClipboardProductivityCategory.communication.rawValue: Color.green,
                    ClipboardProductivityCategory.research.rawValue: Color.purple,
                    ClipboardProductivityCategory.notesAndDrafts.rawValue: Color.orange,
                    ClipboardProductivityCategory.adminText.rawValue: Color.teal,
                    ClipboardProductivityCategory.dataAndNumbers.rawValue: Color.pink,
                ])
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 260)
                .padding(16)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }

            analysisStatusBar
        }
    }

    private var analysisStatusBar: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 12) {
                if let analyzedAt = viewModel.dashboardAnalyzedAt {
                    Text("Last analysis \(DashboardDurationFormatting.analysisAgo(from: analyzedAt, now: context.date))")
                } else {
                    Text("No analysis yet")
                }

                Button("Analyse Now") {
                    viewModel.refreshDashboardAnalysisNow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let nextAt = viewModel.nextDashboardAnalysisAt {
                    if nextAt <= context.date {
                        Text("Next analyse due now")
                    } else {
                        Text("Next analyse \(DashboardDurationFormatting.analysisUntil(nextAt, now: context.date))")
                    }
                } else {
                    Text("Next analyse in 30 minutes")
                }

                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DashboardMetricsSummaryBox: View {
    let unreadMailCount: Int
    let unreadChatCount: Int
    let passwordCount: Int
    let upcomingBillsCount: Int
    let onUnreadEmail: () -> Void
    let onUnreadChat: () -> Void
    let onPasswords: () -> Void
    let onBills: () -> Void

    private static let chatTint = Color(red: 129 / 255, green: 201 / 255, blue: 149 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summary", systemImage: "square.grid.2x2")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SummaryMetricItem(
                        title: "Unread email",
                        value: "\(unreadMailCount)",
                        systemImage: "envelope.badge",
                        tint: .blue,
                        action: onUnreadEmail
                    )

                    Divider()

                    SummaryMetricItem(
                        title: "Unread chat",
                        value: "\(unreadChatCount)",
                        systemImage: "message.badge",
                        tint: Self.chatTint,
                        action: onUnreadChat
                    )
                }

                Divider()

                HStack(spacing: 0) {
                    SummaryMetricItem(
                        title: "Passwords stored",
                        value: "\(passwordCount)",
                        systemImage: "key.fill",
                        tint: .orange,
                        action: onPasswords
                    )

                    Divider()

                    SummaryMetricItem(
                        title: "Bills due soon",
                        value: "\(upcomingBillsCount)",
                        systemImage: "dollarsign.circle",
                        tint: .purple,
                        action: onBills
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct SummaryMetricItem: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)

                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ResourceUsageSummaryCard: View {
    let metrics: DashboardProcessMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.indigo)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metrics?.formattedCPU ?? "—")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("CPU")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(metrics?.formattedMemory ?? "—")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Memory")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Live Nucleus resource usage")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
