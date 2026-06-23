import DatabaseKit
import NucleusCore
import NucleusKit
import SwiftUI

private enum BillEditorContext: Identifiable {
    case add
    case edit(Bill)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let bill): return bill.id.uuidString
        }
    }

    var existingBill: Bill? {
        if case .edit(let bill) = self { return bill }
        return nil
    }
}

struct BillsWorkspaceScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @State private var selectedBillID: UUID?
    @State private var editorContext: BillEditorContext?

    private var summary: BillMonthlySummary {
        viewModel.billMonthlySummary()
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.activeBills.isEmpty {
                    ContentUnavailableView {
                        Label("No bills yet", systemImage: "dollarsign.circle")
                    } description: {
                        Text("Track recurring bills here. They sync with your computer via cloud sync.")
                    } actions: {
                        Button("Add bill") {
                            editorContext = .add
                        }
                        .accessibilityIdentifier("bills.add.empty")
                        Button("Refresh sync") {
                            Task { await viewModel.refreshICloudSync() }
                        }
                    }
                } else {
                    billsList
                }
            }
            .navigationTitle("Bills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorContext = .add
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("bills.add")
                }
            }
            .refreshable {
                await viewModel.refreshICloudSync()
            }
            .sheet(isPresented: Binding(
                get: { selectedBillID != nil },
                set: { if !$0 { selectedBillID = nil } }
            )) {
                if let billID = selectedBillID,
                   let bill = viewModel.bills.first(where: { $0.id == billID }) {
                    MobileBillDetailSheet(
                        bill: bill,
                        payments: viewModel.paymentsForCurrentPeriod(for: bill),
                        remainingAmount: viewModel.remainingAmount(for: bill),
                        status: viewModel.billDisplayStatus(for: bill),
                        onEdit: {
                            selectedBillID = nil
                            editorContext = .edit(bill)
                        },
                        onDelete: {
                            viewModel.deleteBill(id: bill.id)
                            selectedBillID = nil
                        },
                        onLogPayment: { amount, note in
                            viewModel.logBillPayment(billID: bill.id, amount: amount, note: note)
                        }
                    )
                }
            }
            .sheet(item: $editorContext) { context in
                MobileBillEditorSheet(
                    existingBill: context.existingBill,
                    onSave: { bill in
                        viewModel.saveBill(bill)
                    }
                )
            }
        }
    }

    private var billsList: some View {
        List {
            if summary.dueSoonCount > 0 {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(summary.dueSoonCount) due soon")
                                .font(.headline)
                            Text("Across your active bills")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Active bills") {
                ForEach(viewModel.activeBills) { bill in
                    Button {
                        selectedBillID = bill.id
                    } label: {
                        MobileBillRow(
                            bill: bill,
                            remainingAmount: viewModel.remainingAmount(for: bill),
                            status: viewModel.billDisplayStatus(for: bill)
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteBill(id: bill.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

private struct MobileBillRow: View {
    let bill: Bill
    let remainingAmount: Double
    let status: BillDisplayStatus

    private var accent: Color {
        let billAccent = BillScheduleCalculator.dueAccent(
            daysUntilDue: BillScheduleCalculator.daysUntilDue(for: bill.nextDueDate),
            isPaid: remainingAmount <= 0.009
        )
        return Color(red: billAccent.red, green: billAccent.green, blue: billAccent.blue)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bill.resolvedIconName)
                .foregroundStyle(accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(BillScheduleCalculator.dueCountdown(for: bill.nextDueDate))
                    .font(.caption)
                    .foregroundStyle(accent)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(NucleusFormatters.currencyString(remainingAmount, currencyCode: bill.currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status == .overdue ? .red : .primary)
                Text(status.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MobileBillEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

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
    @State private var currencyCode = BillCurrency.aud.rawValue

    private var isEditing: Bool { existingBill != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill details") {
                    TextField("Bill name", text: $name)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(BillCurrency.allCases, id: \.rawValue) { currency in
                            Text(currency.label).tag(currency.rawValue)
                        }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(BillCategory.allCases, id: \.self) { category in
                            Label(category.label, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                }

                Section("Schedule") {
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
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? "Edit bill" : "Add bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveBill()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Double(amount) != nil
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
        currencyCode = existingBill.currencyCode
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

        let resolvedDueDate: Date
        if let existingBill {
            resolvedDueDate = recurrence == .monthly ? existingBill.nextDueDate : nextDueDate
        } else {
            resolvedDueDate = computedDueDate
        }

        let bill = Bill(
            id: existingBill?.id ?? UUID(),
            name: trimmedName,
            amount: parsedAmount,
            currencyCode: currencyCode,
            category: category,
            recurrence: recurrence,
            customIntervalDays: recurrence == .customDays ? customIntervalDays : nil,
            dueDayOfMonth: recurrence == .monthly ? dueDayOfMonth : nil,
            nextDueDate: resolvedDueDate,
            notes: notes,
            isArchived: existingBill?.isArchived ?? false,
            createdAt: existingBill?.createdAt ?? Date(),
            sortOrder: existingBill?.sortOrder ?? 0
        )
        onSave(bill)
        dismiss()
    }
}

private struct MobileBillDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let bill: Bill
    let payments: [BillPayment]
    let remainingAmount: Double
    let status: BillDisplayStatus
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onLogPayment: (Double, String) -> Void

    @State private var showingPaymentForm = false
    @State private var showingDeleteConfirmation = false
    @State private var paymentAmount = ""
    @State private var paymentNote = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Amount") {
                        Text(NucleusFormatters.currencyString(bill.amount, currencyCode: bill.currencyCode))
                    }
                    LabeledContent("Remaining") {
                        Text(NucleusFormatters.currencyString(remainingAmount, currencyCode: bill.currencyCode))
                            .foregroundStyle(status == .overdue ? .red : .primary)
                    }
                    LabeledContent("Due") {
                        Text(NucleusFormatters.dayHeader.string(from: bill.nextDueDate))
                    }
                    LabeledContent("Status") {
                        Text(status.label)
                    }
                    LabeledContent("Recurrence") {
                        Text(bill.recurrence.label)
                    }
                    if !bill.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(bill.notes)
                        }
                    }
                }

                Section("Payments this period") {
                    if payments.isEmpty {
                        Text("No payments logged yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(payments) { payment in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NucleusFormatters.currencyString(payment.amount, currencyCode: bill.currencyCode))
                                        .font(.subheadline.weight(.semibold))
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
                    }
                }
            }
            .navigationTitle(bill.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Edit", action: onEdit)
                    Button("Log payment") {
                        paymentAmount = String(format: "%.2f", remainingAmount > 0 ? remainingAmount : bill.amount)
                        paymentNote = ""
                        showingPaymentForm = true
                    }
                }
            }
            .confirmationDialog("Delete this bill?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Log payment", isPresented: $showingPaymentForm) {
                TextField("Amount", text: $paymentAmount)
                    .keyboardType(.decimalPad)
                TextField("Note (optional)", text: $paymentNote)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    guard let amount = Double(paymentAmount), amount > 0 else { return }
                    onLogPayment(amount, paymentNote)
                    dismiss()
                }
            } message: {
                Text("Record a payment for \(bill.name).")
            }
        }
    }
}
