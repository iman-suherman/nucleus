import DatabaseKit
import NucleusCore
import NucleusKit
import NucleusUI
import SwiftUI

struct DashboardWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @StateObject private var processMetricsService = DashboardProcessMetricsService.shared
    @StateObject private var holidayService = DashboardPublicHolidayService.shared

    private var snapshot: DashboardSnapshot {
        viewModel.dashboardSnapshot()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greetingHeader
                    insightSection
                    publicHolidaySection
                    resourceAndSyncRow
                    statsGrid
                    paymentPreparationSection
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .onAppear {
                processMetricsService.startSamplingIfNeeded()
                viewModel.refreshDashboardQuoteForCurrentContext()
                viewModel.refreshDashboardQuoteEmojis()
                holidayService.refresh(countryCode: Locale.current.region?.identifier)
            }
            .onDisappear {
                processMetricsService.stopSampling()
            }
            .refreshable {
                await viewModel.refreshICloudSync()
                viewModel.refreshDashboardQuoteForCurrentContext()
                viewModel.refreshDashboardQuoteEmojis()
                holidayService.refresh(countryCode: Locale.current.region?.identifier, force: true)
            }
            .onChange(of: holidayService.nextHoliday?.date) { _, _ in
                viewModel.refreshDashboardQuoteForCurrentContext()
                viewModel.refreshDashboardQuoteEmojis()
            }
        }
    }

    private var greetingHeader: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingLine(asOf: context.date))
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(DashboardGreeting.dateLine(now: context.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let quoteLine {
                    DashboardAutoScrollingText(quoteLine, font: .title3)
                }
            }
            .onChange(of: DashboardTimePeriod.current(now: context.date)) { _, _ in
                viewModel.refreshDashboardQuoteForCurrentContext()
                viewModel.refreshDashboardQuoteEmojis()
            }
        }
    }

    private func greetingLine(asOf date: Date) -> String {
        let celebrateHoliday = holidayService.isPublicHoliday(on: date)
        return DashboardGreeting.line(
            firstName: DashboardGreeting.firstName(from: viewModel.iCloudSync.accountName),
            now: date,
            isPublicHoliday: celebrateHoliday,
            publicHolidayName: celebrateHoliday ? holidayService.todayPublicHolidayName(on: date) : nil
        )
    }

    private var quoteLine: String? {
        let quote = sanitizedDashboardQuote
        guard !quote.isEmpty else { return nil }
        return DashboardQuotes.displayBody(
            from: quote,
            emojis: viewModel.dashboardQuoteEmojis
        )
    }

    private var sanitizedDashboardQuote: String {
        viewModel.dashboardQuote
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private var publicHolidaySection: some View {
        DashboardPublicHolidayCard(
            layout: DashboardPublicHolidayService.displayLayout(
                countryGroups: holidayService.countryGroups,
                selectedCountryCodes: [],
                locationCountryCode: Locale.current.region?.identifier
            ),
            isLoading: holidayService.isLoading,
            statusMessage: holidayService.statusMessage
        )
    }

    private var resourceAndSyncRow: some View {
        HStack(alignment: .top, spacing: 12) {
            DashboardResourceUsageCard(metrics: processMetricsService.metrics)
                .frame(maxWidth: .infinity, alignment: .leading)

            DashboardCloudSyncCard(
                syncService: viewModel.iCloudSync,
                notesService: viewModel.notesService,
                onRefresh: {
                    Task { await viewModel.refreshICloudSync() }
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: "Notes",
                value: "\(viewModel.regularNotes.count)",
                icon: "note.text",
                tint: .blue
            ) {
                viewModel.selectedTab = .notes
            }
            StatCard(
                title: "Passwords",
                value: "\(viewModel.passwordNotes.count)",
                icon: "key.fill",
                tint: .orange
            ) {
                viewModel.selectedTab = .passwords
            }
            StatCard(
                title: "Bills due",
                value: "\(snapshot.upcomingBills.count)",
                badgeCount: viewModel.billsNearlyDueCount,
                icon: "dollarsign.circle",
                tint: .green
            ) {
                viewModel.selectedTab = .bills
            }
            StatCard(
                title: "Active bills",
                value: "\(viewModel.activeBills.count)",
                icon: "list.bullet.rectangle",
                tint: .purple
            ) {
                viewModel.selectedTab = .bills
            }
        }
    }

    private var insightSection: some View {
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

    private var paymentPreparationSection: some View {
        let summary = viewModel.billPaymentSummary()

        return VStack(alignment: .leading, spacing: 14) {
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
                if viewModel.billsNearlyDueCount > 0 {
                    MobileCountBadge(count: viewModel.billsNearlyDueCount, kind: .warning)
                }
                Spacer()
                Button("Open Bills") {
                    viewModel.selectedTab = .bills
                }
                .font(.subheadline)
            }

            if summary.groups.isEmpty {
                Text("Nothing to prepare in the next two weeks.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(summary.groups) { group in
                        HStack(spacing: 12) {
                            Image(systemName: group.category.systemImage)
                                .foregroundStyle(.purple)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(group.category.label) · \(group.currencyCode)")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(group.billCount == 1 ? "1 bill" : "\(group.billCount) bills") due \(DashboardInsightsEngine.dueWindowRelativePhrase(from: group.earliestDueDate, to: group.latestDueDate))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                if group.billCount > 0 {
                                    MobileCountBadge(count: group.billCount, kind: .warning)
                                }
                                Text(NucleusFormatters.currencyString(group.totalAmount, currencyCode: group.currencyCode))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if group.id != summary.groups.last?.id {
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

                if !summary.preparationNotes.isEmpty {
                    Text(summary.preparationNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var badgeCount: Int = 0
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                    if badgeCount > 0 {
                        MobileCountBadge(count: badgeCount, kind: .warning)
                    }
                }
                Text(value)
                    .font(.title2.bold().monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
