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
                    summaryCards
                    resourceUsageSection
                    cloudSyncSection
                    summaryAndBillsRow
                    productivitySection
                }
                .padding(28)
                .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            weatherService.refreshIfNeeded()
            processMetricsService.startSamplingIfNeeded()
        }
        .onDisappear {
            processMetricsService.stopSampling()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(DashboardGreeting.timeOfDay()), \(DashboardGreeting.firstName)")
                        .font(.largeTitle.bold())

                    weatherGreetingLine
                }

                Spacer(minLength: 0)

                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 4)
            }

            Text("Your workspace at a glance — bills, messages, passwords, and activity patterns.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            analysisStatusRow
        }
    }

    @ViewBuilder
    private var weatherGreetingLine: some View {
        if let weather = weatherService.weather {
            HStack(spacing: 8) {
                Image(systemName: weather.conditionSymbol)
                    .symbolRenderingMode(.multicolor)
                Text("Today: \(weather.conditionDescription). High \(weather.highTemperature), low \(weather.lowTemperature).")
                if let rainSummary = weather.rainSummary {
                    Text(rainSummary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if weatherService.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading today's weather…")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if let statusMessage = weatherService.statusMessage {
            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var analysisStatusRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let analyzedAt = viewModel.dashboardAnalyzedAt {
                    Text("Last analysis \(analyzedAt, style: .relative)")
                } else {
                    Text("No analysis yet")
                }

                if let nextAt = viewModel.nextDashboardAnalysisAt {
                    if nextAt <= Date() {
                        Text("Next analysis due now")
                    } else {
                        Text("Next analysis \(nextAt, style: .relative)")
                    }
                } else {
                    Text("Next analysis runs every 30 minutes")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Analyze Now") {
                viewModel.refreshDashboardAnalysisNow()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            SummaryMetricCard(
                title: "Unread email",
                value: "\(snapshot.unreadMailCount)",
                systemImage: "envelope.badge",
                tint: .blue,
                action: { viewModel.sidebarSelection = .workspace(.inbox) }
            )
            SummaryMetricCard(
                title: "Unread chat",
                value: "\(snapshot.unreadChatCount)",
                systemImage: "message.badge",
                tint: Color(red: 129 / 255, green: 201 / 255, blue: 149 / 255),
                action: { viewModel.sidebarSelection = .workspace(.chat) }
            )
            SummaryMetricCard(
                title: "Passwords stored",
                value: "\(snapshot.passwordCount)",
                systemImage: "key.fill",
                tint: .orange,
                action: { viewModel.sidebarSelection = .workspace(.notes) }
            )
            SummaryMetricCard(
                title: "Bills due soon",
                value: "\(snapshot.upcomingBills.count)",
                systemImage: "dollarsign.circle",
                tint: .purple,
                action: { viewModel.sidebarSelection = .workspace(.bills) }
            )
        }
    }

    private var resourceUsageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Resource usage", systemImage: "gauge.with.dots.needle.67percent")
                .font(.headline)

            Text("Live CPU and memory for Nucleus on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ResourceMetricTile(
                    title: "CPU",
                    value: processMetricsService.metrics?.formattedCPU ?? "—",
                    systemImage: "cpu",
                    tint: .blue
                )
                ResourceMetricTile(
                    title: "Memory",
                    value: processMetricsService.metrics?.formattedMemory ?? "—",
                    systemImage: "memorychip",
                    tint: .teal
                )
            }
        }
    }

    private var cloudSyncSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Cloud sync", systemImage: "icloud")
                .font(.headline)

            VStack(spacing: 0) {
                cloudSyncRow(
                    title: "Nucleus Cloud",
                    systemImage: "cloud",
                    isConnected: cloudSyncService.status.isConnected,
                    statusLabel: cloudSyncService.status.label,
                    connectTitle: isConnectingNucleusCloud ? "Opening Browser…" : "Connect",
                    isConnectDisabled: isConnectingNucleusCloud,
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
                    onConnect: connectICloud
                )
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))

            if let nucleusCloudMessage {
                Text(nucleusCloudMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            Task { await syncService.refreshAccountStatus() }
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
        onConnect: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : systemImage)
                .foregroundStyle(isConnected ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !isConnected {
                Button(connectTitle, action: onConnect)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isConnectDisabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summaryAndBillsRow: some View {
        HStack(alignment: .top, spacing: 20) {
            intelligentSummary
                .frame(maxWidth: .infinity, alignment: .leading)
            upcomingBillsSection
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var intelligentSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Intelligent summary", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(snapshot.activitySummary.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(snapshot.productivitySummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var upcomingBillsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Upcoming bills", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                Button("Open Bills") {
                    viewModel.sidebarSelection = .workspace(.bills)
                }
            }

            if snapshot.upcomingBills.isEmpty {
                Text("Nothing due in the next two weeks.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            } else {
                billPaymentPreparationCard

                VStack(spacing: 0) {
                    ForEach(snapshot.upcomingBills) { bill in
                        Button {
                            viewModel.selectedBillID = bill.id
                            viewModel.sidebarSelection = .workspace(.bills)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: bill.category.systemImage)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(bill.name)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    HStack(spacing: 4) {
                                        Text(NucleusFormatters.dayHeader.string(from: bill.dueDate))
                                        Text("·")
                                        Text(bill.dueDate, style: .relative)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(NucleusFormatters.currencyString(bill.amountDue, currencyCode: bill.currencyCode))
                                        .font(.subheadline.monospacedDigit())
                                    Text(bill.status.label)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(statusColor(for: bill.status))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if bill.id != snapshot.upcomingBills.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var billPaymentPreparationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Payment preparation", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text(billPaymentSummary.preparationNotes)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if group.id != billPaymentSummary.groups.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
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
        }
    }

    private func statusColor(for status: BillDisplayStatus) -> Color {
        switch status {
        case .paid: return .green
        case .upcoming: return .secondary
        case .dueSoon: return .orange
        case .partial: return .yellow
        case .overdue: return .red
        }
    }
}

private struct ResourceMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var highlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                    Spacer()
                    if highlighted {
                        Text("Vault")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(tint)
                    }
                }

                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                highlighted ? tint.opacity(0.1) : Color(nsColor: .controlBackgroundColor).opacity(0.55),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(highlighted ? tint.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
