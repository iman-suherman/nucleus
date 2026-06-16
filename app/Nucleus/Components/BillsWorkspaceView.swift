import DatabaseKit
import NucleusKit
import SwiftUI
import SyncKit
import UniformTypeIdentifiers

struct BillsWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var syncService = CloudKitSyncService.shared
    @State private var showingAddBill = false
    @State private var showingLogPayment = false
    @State private var showingPartialPayment = false
    @State private var showingBillDetail = false
    @State private var showingIncomeEditor = false
    @State private var showingImportPanel = false
    @State private var showingExportPanel = false
    @State private var exportDocument = BillCSVDocument(text: "")
    @State private var importMessage: String?
    @State private var calendarMonth = Date()

    private var summary: BillMonthlySummary {
        viewModel.billMonthlySummary(expectedIncome: appSettings.expectedMonthlyIncome)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            billList
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            summarySidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingAddBill) {
            BillEditorSheet(mode: .add) { bill in
                viewModel.saveBill(bill)
            }
        }
        .sheet(isPresented: $showingLogPayment) {
            if let bill = viewModel.selectedBill {
                LogPaymentSheet(bill: bill, mode: .full) { amount, note in
                    viewModel.logBillPayment(billID: bill.id, amount: amount, note: note)
                }
            }
        }
        .sheet(isPresented: $showingPartialPayment) {
            if let bill = viewModel.selectedBill {
                LogPaymentSheet(
                    bill: bill,
                    mode: .partial,
                    suggestedAmount: viewModel.remainingAmount(for: bill)
                ) { amount, note in
                    viewModel.logBillPayment(billID: bill.id, amount: amount, note: note)
                }
            }
        }
        .sheet(isPresented: $showingBillDetail) {
            if let bill = viewModel.selectedBill {
                BillDetailSheet(
                    bill: bill,
                    payments: viewModel.payments(for: bill.id),
                    averageAmount: viewModel.averagePayment(for: bill.id),
                    remainingAmount: viewModel.remainingAmount(for: bill)
                ) { updated in
                    viewModel.saveBill(updated)
                } onDelete: {
                    viewModel.deleteBill(id: bill.id)
                }
            }
        }
        .sheet(isPresented: $showingIncomeEditor) {
            IncomeEditorSheet(amount: appSettings.expectedMonthlyIncome) { amount in
                appSettings.expectedMonthlyIncome = amount
            }
        }
        .fileImporter(
            isPresented: $showingImportPanel,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showingExportPanel,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "nucleus-bills-export"
        ) { result in
            if case .failure(let error) = result {
                importMessage = error.localizedDescription
            }
        }
        .alert("Bills", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let outcome = viewModel.importBillsFromCSV(text)
                if outcome.errors.isEmpty {
                    importMessage = "Imported \(outcome.billsImported) bill(s) and \(outcome.paymentsImported) payment(s)."
                } else {
                    importMessage = "Imported \(outcome.billsImported) bill(s) and \(outcome.paymentsImported) payment(s) with \(outcome.errors.count) warning(s).\n\(outcome.errors.prefix(3).joined(separator: "\n"))"
                }
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    private var billList: some View {
        VStack(spacing: 0) {
            billListHeader

            Group {
                if viewModel.activeBills.isEmpty {
                    billsEmptyState
                } else {
                    billsTable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            billActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            calendarMonth = initialCalendarMonth()
        }
        .onChange(of: viewModel.activeBills.count) { _, _ in
            calendarMonth = initialCalendarMonth()
        }
    }

    private var billsTable: some View {
        VStack(spacing: 0) {
            billColumnHeader

            List(selection: $viewModel.selectedBillID) {
                ForEach(viewModel.activeBills) { bill in
                    BillRowView(
                        bill: bill,
                        averageAmount: viewModel.averagePayment(for: bill.id) ?? bill.amount,
                        remainingAmount: viewModel.remainingAmount(for: bill),
                        status: viewModel.billDisplayStatus(for: bill),
                        progress: viewModel.billStatusProgress(for: bill),
                        onOpen: {
                            viewModel.selectedBillID = bill.id
                            showingBillDetail = true
                        }
                    )
                    .tag(Optional(bill.id))
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func initialCalendarMonth() -> Date {
        let calendar = Calendar.current
        let nearestDue = viewModel.activeBills
            .map(\.nextDueDate)
            .min()
        guard let nearestDue else { return Date() }
        return calendar.date(from: calendar.dateComponents([.year, .month], from: nearestDue)) ?? Date()
    }

    private var billsEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No bills yet")
                    .font(.title2.bold())
                Text("Track recurring bills, log payments, and see what's still due this month.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 12) {
                Button {
                    showingImportPanel = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingAddBill = true
                } label: {
                    Label("Add Bill", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 8) {
                Text("Use the bundled sample CSV modeled on Chronicle Pro bills, or export from Nucleus anytime.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

                Button("Save Sample CSV…") {
                    exportDocument = BillCSVDocument(text: viewModel.sampleBillsCSV())
                    showingExportPanel = true
                }
                .buttonStyle(.link)
            }

            if NucleusDatabase.usesCloudKitSync {
                Label("Bills sync via iCloud — use Settings → iCloud → Upload Bills to iCloud", systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var billListHeader: some View {
        HStack {
            Text("Bills")
                .font(.title2.bold())
            Spacer()

            if NucleusDatabase.usesCloudKitSync {
                Label("iCloud", systemImage: syncService.status.isAvailable ? "icloud.fill" : "icloud.slash")
                    .font(.caption)
                    .foregroundStyle(syncService.status.isAvailable ? .blue : .secondary)
            }

            Menu {
                Button {
                    showingImportPanel = true
                } label: {
                    Label("Import CSV…", systemImage: "square.and.arrow.down")
                }
                Button {
                    exportDocument = BillCSVDocument(text: viewModel.exportBillsCSV())
                    showingExportPanel = true
                } label: {
                    Label("Export CSV…", systemImage: "square.and.arrow.up")
                }
                Button {
                    exportDocument = BillCSVDocument(text: viewModel.sampleBillsCSV())
                    showingExportPanel = true
                } label: {
                    Label("Save Sample CSV…", systemImage: "doc.text")
                }
            } label: {
                Label("Import / Export", systemImage: "arrow.up.arrow.down.circle")
            }
            .menuStyle(.borderlessButton)

            Text("\(viewModel.activeBills.count) active")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var billColumnHeader: some View {
        HStack(spacing: 12) {
            Text("Bill")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Average")
                .frame(width: 90, alignment: .trailing)
            Text("Amount")
                .frame(width: 90, alignment: .trailing)
            Text("Next Due Date")
                .frame(width: 170, alignment: .leading)
            Color.clear.frame(width: 8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var billActionBar: some View {
        HStack(spacing: 12) {
            Menu {
                Button {
                    showingAddBill = true
                } label: {
                    Label("Add Bill", systemImage: "plus")
                }
                Button {
                    showingImportPanel = true
                } label: {
                    Label("Import CSV…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }

            Button {
                showingLogPayment = true
            } label: {
                Text("Log Payment")
            }
            .disabled(viewModel.selectedBill == nil)

            Button {
                showingPartialPayment = true
            } label: {
                Text("Log Partial")
            }
            .disabled(viewModel.selectedBill == nil)

            Button {
                showingBillDetail = true
            } label: {
                Text("View")
            }
            .disabled(viewModel.selectedBill == nil)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var summarySidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BillCalendarView(
                    month: calendarMonth,
                    dueDates: BillScheduleCalculator.dueDates(in: calendarMonth, bills: viewModel.activeBills),
                    onPreviousMonth: { calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth },
                    onNextMonth: { calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth }
                )

                BillStatCard(
                    title: "Bills Due Soon",
                    count: summary.dueSoonCount,
                    amount: summary.dueSoonAmount
                )

                BillStatCard(
                    title: "Bills Due This Month",
                    count: summary.dueThisMonthCount,
                    amount: summary.dueThisMonthAmount
                )

                BillStatCard(
                    title: "Bills Paid This Month",
                    count: summary.paidThisMonthCount,
                    amount: summary.paidThisMonthAmount,
                    emphasize: true
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Monthly Balance")
                        .font(.headline)

                    BillBalanceRow(label: "Expected Total Income", amount: summary.expectedIncome)
                    BillBalanceRow(label: "Paid This Month", amount: summary.paidThisMonthAmount)
                    BillBalanceRow(label: "Still Due This Month", amount: summary.stillDueThisMonthAmount)

                    Divider()

                    HStack {
                        Text("OK To Spend")
                            .font(.headline)
                        Spacer()
                        Text(NucleusFormatters.currencyString(summary.okToSpend))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(summary.okToSpend >= 0 ? Color.primary : Color.red)
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    showingIncomeEditor = true
                } label: {
                    Label("New Income", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }
}

private struct BillCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private enum BillStatusStyle {
    static func accent(for bill: Bill, remainingAmount: Double) -> Color {
        let accent = BillScheduleCalculator.dueAccent(
            daysUntilDue: BillScheduleCalculator.daysUntilDue(for: bill.nextDueDate),
            isPaid: remainingAmount <= 0.009
        )
        return Color(red: accent.red, green: accent.green, blue: accent.blue)
    }

    static func dueLabel(for bill: Bill, remainingAmount: Double) -> String {
        let relative = BillScheduleCalculator.dueCountdown(for: bill.nextDueDate)
        if remainingAmount <= 0.009 {
            return "Paid · \(relative)"
        }
        return relative
    }
}

private struct BillRowView: View {
    let bill: Bill
    let averageAmount: Double
    let remainingAmount: Double
    let status: BillDisplayStatus
    let progress: Double
    var onOpen: (() -> Void)?

    private var accent: Color { BillStatusStyle.accent(for: bill, remainingAmount: remainingAmount) }
    private var isOverdue: Bool {
        remainingAmount > 0.009 && BillScheduleCalculator.daysUntilDue(for: bill.nextDueDate) < 0
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: bill.resolvedIconName)
                    .foregroundStyle(accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.name)
                        .font(.body.weight(.semibold))
                    Text(bill.recurrence.repeatsDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(NucleusFormatters.currencyString(averageAmount))
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(.secondary)

            Text(NucleusFormatters.currencyString(remainingAmount))
                .frame(width: 90, alignment: .trailing)
                .fontWeight(.medium)
                .foregroundStyle(isOverdue ? .red : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(BillStatusStyle.dueLabel(for: bill, remainingAmount: remainingAmount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(NucleusFormatters.dayHeader.string(from: bill.nextDueDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 170, alignment: .leading)

            BillDueProgressBar(progress: progress, accent: accent)
                .frame(width: 8, height: 44)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("Double-click to view bill details")
        .onTapGesture(count: 2) {
            onOpen?()
        }
    }
}

private struct BillDueProgressBar: View {
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent.opacity(0.18))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent)
                    .frame(height: max(4, proxy.size.height * progress))
            }
        }
    }
}

private struct BillStatCard: View {
    let title: String
    let count: Int
    let amount: Double
    var emphasize: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count) bill\(count == 1 ? "" : "s")")
                .font(.title3.bold())
            Text(NucleusFormatters.currencyString(amount))
                .font(.title2.bold())
                .foregroundStyle(emphasize ? .green : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BillBalanceRow: View {
    let label: String
    let amount: Double

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(NucleusFormatters.currencyString(amount))
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct BillCalendarView: View {
    let month: Date
    let dueDates: Set<DateComponents>
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onPreviousMonth) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button(action: onNextMonth) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }

            let days = weekdaySymbols
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(calendarDays, id: \.self) { day in
                    if let day {
                        VStack(spacing: 4) {
                            Text("\(day)")
                                .font(.caption)
                            Circle()
                                .fill(hasDueDate(day) ? Color.green : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }

    private var weekdaySymbols: [String] {
        calendar.shortWeekdaySymbols
    }

    private var calendarDays: [Int?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Int?] = Array(repeating: nil, count: leadingBlanks)
        days.append(contentsOf: dayRange.map(Optional.some))
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private func hasDueDate(_ day: Int) -> Bool {
        let components = calendar.dateComponents([.year, .month], from: month)
        var dueComponents = DateComponents()
        dueComponents.year = components.year
        dueComponents.month = components.month
        dueComponents.day = day
        return dueDates.contains { $0.year == dueComponents.year && $0.month == dueComponents.month && $0.day == dueComponents.day }
    }
}

private enum BillEditorMode {
    case add
    case edit
}

private struct BillEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: BillEditorMode
    var existingBill: Bill?
    let onSave: (Bill) -> Void

    @State private var name = ""
    @State private var amount = ""
    @State private var category: BillCategory = .other
    @State private var recurrence: BillRecurrence = .monthly
    @State private var dueDayOfMonth = 1
    @State private var nextDueDate = Date()
    @State private var customIntervalDays = 30
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .add ? "Add Bill" : "Edit Bill")
                .font(.title2.bold())

            Form {
                TextField("Bill name", text: $name)
                TextField("Amount", text: $amount)
                Picker("Category", selection: $category) {
                    ForEach(BillCategory.allCases, id: \.self) { category in
                        Label(category.rawValue.capitalized, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                Picker("Repeats", selection: $recurrence) {
                    ForEach(BillRecurrence.allCases, id: \.self) { recurrence in
                        Text(recurrence.label).tag(recurrence)
                    }
                }
                if recurrence == .monthly {
                    Stepper("Due day: \(dueDayOfMonth)", value: $dueDayOfMonth, in: 1...31)
                } else if recurrence == .customDays {
                    Stepper("Every \(customIntervalDays) days", value: $customIntervalDays, in: 1...365)
                    DatePicker("Next due date", selection: $nextDueDate, displayedComponents: .date)
                } else {
                    DatePicker("Next due date", selection: $nextDueDate, displayedComponents: .date)
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saveBill()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(amount) == nil)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let existingBill else { return }
        name = existingBill.name
        amount = String(format: "%.2f", existingBill.amount)
        category = existingBill.category
        recurrence = existingBill.recurrence
        dueDayOfMonth = existingBill.dueDayOfMonth ?? 1
        nextDueDate = existingBill.nextDueDate
        customIntervalDays = existingBill.customIntervalDays ?? 30
        notes = existingBill.notes
    }

    private func saveBill() {
        guard let parsedAmount = Double(amount) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let computedDueDate = recurrence == .monthly
            ? BillScheduleCalculator.initialNextDueDate(
                recurrence: recurrence,
                dueDayOfMonth: dueDayOfMonth,
                anchorDate: Date()
            )
            : nextDueDate

        let bill = Bill(
            id: existingBill?.id ?? UUID(),
            name: trimmedName,
            amount: parsedAmount,
            category: category,
            recurrence: recurrence,
            customIntervalDays: recurrence == .customDays ? customIntervalDays : nil,
            dueDayOfMonth: recurrence == .monthly ? dueDayOfMonth : nil,
            nextDueDate: existingBill?.nextDueDate ?? computedDueDate,
            notes: notes,
            isArchived: existingBill?.isArchived ?? false,
            createdAt: existingBill?.createdAt ?? Date(),
            sortOrder: existingBill?.sortOrder ?? 0
        )
        onSave(bill)
        dismiss()
    }
}

private enum PaymentSheetMode {
    case full
    case partial
}

private struct LogPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let bill: Bill
    let mode: PaymentSheetMode
    var suggestedAmount: Double?
    let onSave: (Double, String) -> Void

    @State private var amount = ""
    @State private var note = ""
    @State private var paidAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .full ? "Log Payment" : "Log Partial Payment")
                .font(.title2.bold())

            Text(bill.name)
                .foregroundStyle(.secondary)

            Form {
                TextField("Amount", text: $amount)
                DatePicker("Paid on", selection: $paidAt, displayedComponents: [.date, .hourAndMinute])
                TextField("Note", text: $note)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Payment") {
                    guard let parsedAmount = Double(amount), parsedAmount > 0 else { return }
                    onSave(parsedAmount, note)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Double(amount) == nil || (Double(amount) ?? 0) <= 0)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            if mode == .full {
                amount = String(format: "%.2f", bill.amount)
            } else if let suggestedAmount {
                amount = String(format: "%.2f", suggestedAmount)
            }
        }
    }
}

private struct BillDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let bill: Bill
    let payments: [BillPayment]
    let averageAmount: Double?
    let remainingAmount: Double
    let onSave: (Bill) -> Void
    let onDelete: () -> Void

    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: bill.resolvedIconName)
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(bill.name)
                        .font(.title2.bold())
                    Text(bill.recurrence.repeatsDescription)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit") { showingEditor = true }
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Amount").foregroundStyle(.secondary)
                    Text(NucleusFormatters.currencyString(bill.amount))
                }
                GridRow {
                    Text("Average").foregroundStyle(.secondary)
                    Text(NucleusFormatters.currencyString(averageAmount ?? bill.amount))
                }
                GridRow {
                    Text("Remaining").foregroundStyle(.secondary)
                    Text(NucleusFormatters.currencyString(remainingAmount))
                }
                GridRow {
                    Text("Next due").foregroundStyle(.secondary)
                    Text(NucleusFormatters.dayHeader.string(from: bill.nextDueDate))
                }
            }

            if !bill.notes.isEmpty {
                Text(bill.notes)
                    .foregroundStyle(.secondary)
            }

            Text("Payment History")
                .font(.headline)

            if payments.isEmpty {
                Text("No payments recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(payments) { payment in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(NucleusFormatters.currencyString(payment.amount))
                                .fontWeight(.semibold)
                            if !payment.note.isEmpty {
                                Text(payment.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(NucleusFormatters.dayHeader.string(from: payment.paidAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 180, maxHeight: 260)
            }

            HStack {
                Button("Delete Bill", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 520, height: 560)
        .sheet(isPresented: $showingEditor) {
            BillEditorSheet(mode: .edit, existingBill: bill) { updated in
                onSave(updated)
            }
        }
    }
}

private struct IncomeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let amount: Double
    let onSave: (Double) -> Void

    @State private var income = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Expected Monthly Income")
                .font(.title2.bold())

            TextField("Amount", text: $income)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(Double(income) ?? 0)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            income = String(format: "%.2f", amount)
        }
    }
}
