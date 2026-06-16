import Charts
import NucleusKit
import SwiftUI

struct DashboardWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var snapshot: DashboardSnapshot {
        viewModel.dashboardSnapshot()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                summaryCards
                summaryAndBillsRow
                productivitySection
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Dashboard")
                    .font(.largeTitle.bold())
            }
            Text("Your workspace at a glance — bills, messages, passwords, and activity patterns.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let analyzedAt = viewModel.dashboardAnalyzedAt {
                Text("Last analysis \(analyzedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                VStack(spacing: 0) {
                    ForEach(snapshot.upcomingBills) { bill in
                        Button {
                            viewModel.selectedBillID = bill.id
                            viewModel.sidebarSelection = .workspace(.bills)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bill.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(NucleusFormatters.dayHeader.string(from: bill.dueDate))
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

    private var productivitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Clipboard productivity", systemImage: "chart.bar.fill")
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
