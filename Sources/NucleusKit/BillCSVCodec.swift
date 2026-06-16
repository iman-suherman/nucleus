import Foundation

public struct BillCSVImportResult: Sendable {
    public var billsImported: Int
    public var paymentsImported: Int
    public var errors: [String]

    public init(billsImported: Int = 0, paymentsImported: Int = 0, errors: [String] = []) {
        self.billsImported = billsImported
        self.paymentsImported = paymentsImported
        self.errors = errors
    }
}

public enum BillCSVCodec {
    public static let headerColumns = [
        "type",
        "name",
        "amount",
        "category",
        "recurrence",
        "custom_interval_days",
        "due_day_of_month",
        "next_due_date",
        "currency",
        "notes",
        "archived",
        "bill_name",
        "paid_at",
        "payment_amount",
        "payment_note",
    ]

    public static func exportCSV(bills: [Bill], payments: [BillPayment]) -> String {
        var rows: [String] = [headerColumns.joined(separator: ",")]
        let sortedBills = bills.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        for bill in sortedBills {
            rows.append(encodeBillRow(bill))
        }

        let paymentsByBill = Dictionary(grouping: payments, by: \.billID)
        for bill in sortedBills {
            let billPayments = (paymentsByBill[bill.id] ?? []).sorted { $0.paidAt > $1.paidAt }
            for payment in billPayments {
                rows.append(encodePaymentRow(payment, billName: bill.name))
            }
        }

        return rows.joined(separator: "\n") + "\n"
    }

    public static func importCSV(
        _ text: String,
        existingBills: [Bill] = [],
        referenceDate: Date = Date()
    ) -> (bills: [Bill], payments: [BillPayment], result: BillCSVImportResult) {
        let rows = parseRows(text)
        guard !rows.isEmpty else {
            return ([], [], BillCSVImportResult(errors: ["CSV file is empty."]))
        }

        var headerIndex: [String: Int] = [:]
        var dataRows: [[String]] = []

        if let first = rows.first, first.first?.lowercased() == "type" {
            for (index, column) in first.enumerated() {
                headerIndex[normalizeColumn(column)] = index
            }
            dataRows = Array(rows.dropFirst())
        } else {
            return ([], [], BillCSVImportResult(errors: ["CSV must include a header row starting with \"type\"."]))
        }

        var billsByKey: [String: Bill] = Dictionary(
            uniqueKeysWithValues: existingBills.map { (normalizedBillKey($0.name), $0) }
        )
        var payments: [BillPayment] = []
        var errors: [String] = []
        var billsImported = 0
        var paymentsImported = 0
        var sortOrder = (existingBills.map(\.sortOrder).max() ?? -1) + 1

        for (rowIndex, row) in dataRows.enumerated() {
            let lineNumber = rowIndex + 2
            let type = value(row, headerIndex, "type").lowercased()
            guard !type.isEmpty else { continue }

            switch type {
            case "bill":
                do {
                    let bill = try parseBillRow(row, headerIndex: headerIndex, sortOrder: sortOrder, referenceDate: referenceDate)
                    let key = normalizedBillKey(bill.name)
                    if billsByKey[key] == nil {
                        billsImported += 1
                        sortOrder += 1
                    }
                    billsByKey[key] = bill
                } catch {
                    errors.append("Line \(lineNumber): \(error.localizedDescription)")
                }
            case "payment":
                do {
                    let payment = try parsePaymentRow(row, headerIndex: headerIndex, billsByKey: billsByKey)
                    payments.append(payment)
                    paymentsImported += 1
                } catch {
                    errors.append("Line \(lineNumber): \(error.localizedDescription)")
                }
            default:
                errors.append("Line \(lineNumber): Unknown type \"\(type)\".")
            }
        }

        let bills = billsByKey.values.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return (bills, payments, BillCSVImportResult(
            billsImported: billsImported,
            paymentsImported: paymentsImported,
            errors: errors
        ))
    }

    private static func encodeBillRow(_ bill: Bill) -> String {
        [
            "bill",
            bill.name,
            formatAmount(bill.amount),
            bill.category.rawValue,
            bill.recurrence.rawValue,
            bill.customIntervalDays.map(String.init) ?? "",
            bill.dueDayOfMonth.map(String.init) ?? "",
            formatDate(bill.nextDueDate),
            bill.currencyCode,
            bill.notes,
            bill.isArchived ? "true" : "false",
            "",
            "",
            "",
            "",
        ].map(escapeCSV).joined(separator: ",")
    }

    private static func encodePaymentRow(_ payment: BillPayment, billName: String) -> String {
        [
            "payment",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            billName,
            formatDateTime(payment.paidAt),
            formatAmount(payment.amount),
            payment.note,
        ].map(escapeCSV).joined(separator: ",")
    }

    private static func parseBillRow(
        _ row: [String],
        headerIndex: [String: Int],
        sortOrder: Int,
        referenceDate: Date
    ) throws -> Bill {
        let name = value(row, headerIndex, "name")
        guard !name.isEmpty else {
            throw BillCSVError.missingField("name")
        }

        let amount = parseAmount(value(row, headerIndex, "amount")) ?? 0
        let category = BillCategory(rawValue: value(row, headerIndex, "category").lowercased()) ?? .other
        let recurrence = parseRecurrence(value(row, headerIndex, "recurrence"))
        let customDays = Int(value(row, headerIndex, "custom_interval_days"))
        let dueDay = Int(value(row, headerIndex, "due_day_of_month"))
        let archived = parseBool(value(row, headerIndex, "archived"))
        let notes = value(row, headerIndex, "notes")
        let currencyCode = value(row, headerIndex, "currency").uppercased()
        let resolvedCurrency = currencyCode.isEmpty ? BillCurrency.aud.rawValue : currencyCode

        let nextDue: Date
        if let parsedDue = parseDate(value(row, headerIndex, "next_due_date")) {
            nextDue = parsedDue
        } else if recurrence == .monthly {
            nextDue = BillScheduleCalculator.initialNextDueDate(
                recurrence: recurrence,
                dueDayOfMonth: dueDay,
                anchorDate: referenceDate
            )
        } else {
            nextDue = Calendar.current.startOfDay(for: referenceDate)
        }

        let id = UUID(uuidString: value(row, headerIndex, "id")) ?? UUID()

        return Bill(
            id: id,
            name: name,
            amount: amount,
            currencyCode: resolvedCurrency,
            category: category,
            recurrence: recurrence,
            customIntervalDays: customDays,
            dueDayOfMonth: dueDay,
            nextDueDate: nextDue,
            notes: notes,
            isArchived: archived,
            sortOrder: sortOrder
        )
    }

    private static func parsePaymentRow(
        _ row: [String],
        headerIndex: [String: Int],
        billsByKey: [String: Bill]
    ) throws -> BillPayment {
        let billName = value(row, headerIndex, "bill_name")
        guard !billName.isEmpty else {
            throw BillCSVError.missingField("bill_name")
        }

        guard let bill = billsByKey[normalizedBillKey(billName)] else {
            throw BillCSVError.unknownBill(billName)
        }

        let amount = parseAmount(value(row, headerIndex, "payment_amount"))
            ?? parseAmount(value(row, headerIndex, "amount"))
        guard let amount, amount > 0 else {
            throw BillCSVError.missingField("payment_amount")
        }

        let paidAt = parseDateTime(value(row, headerIndex, "paid_at")) ?? Date()
        let note = value(row, headerIndex, "payment_note")
        let id = UUID(uuidString: value(row, headerIndex, "id")) ?? UUID()

        return BillPayment(id: id, billID: bill.id, amount: amount, paidAt: paidAt, note: note)
    }

    private static func parseRows(_ text: String) -> [[String]] {
        text.split(whereSeparator: \.isNewline).map { line in
            parseCSVLine(String(line))
        }.filter { !$0.allSatisfy(\.isEmpty) }
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if char == ",", !inQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index = line.index(after: index)
        }
        values.append(current)
        return values
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func normalizeColumn(_ column: String) -> String {
        column.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedBillKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func value(_ row: [String], _ headerIndex: [String: Int], _ key: String) -> String {
        guard let index = headerIndex[key], index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseRecurrence(_ raw: String) -> BillRecurrence {
        switch raw.lowercased().replacingOccurrences(of: " ", with: "") {
        case "monthly", "everymonth", "month": return .monthly
        case "every30days", "30days", "30": return .every30Days
        case "weekly", "week": return .weekly
        case "yearly", "year", "annual": return .yearly
        case "customdays", "custom": return .customDays
        default: return BillRecurrence(rawValue: raw.lowercased()) ?? .monthly
        }
    }

    private static func parseAmount(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private static func parseBool(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "1", "true", "yes", "y": return true
        default: return false
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatters = [
            "yyyy-MM-dd",
            "d/M/yyyy",
            "M/d/yyyy",
            "dd MMM yyyy",
        ]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    private static func parseDateTime(_ raw: String) -> Date? {
        if let date = parseDate(raw) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func formatAmount(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }
}

private enum BillCSVError: LocalizedError {
    case missingField(String)
    case unknownBill(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let field):
            return "Missing required field \"\(field)\"."
        case .unknownBill(let name):
            return "Unknown bill \"\(name)\" — add a bill row before its payments."
        }
    }
}
