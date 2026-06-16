import Foundation

public enum BillRecurrence: String, Codable, CaseIterable, Sendable {
    case monthly
    case every30Days
    case weekly
    case yearly
    case customDays

    public var label: String {
        switch self {
        case .monthly: return "Every month"
        case .every30Days: return "Every 30 days"
        case .weekly: return "Every week"
        case .yearly: return "Every year"
        case .customDays: return "Custom interval"
        }
    }

    public var repeatsDescription: String {
        "Repeats: \(label.lowercased())"
    }
}

public enum BillCategory: String, Codable, CaseIterable, Sendable {
    case housing
    case utilities
    case subscription
    case credit
    case insurance
    case gift
    case other

    public var systemImage: String {
        switch self {
        case .housing: return "house.fill"
        case .utilities: return "drop.fill"
        case .subscription: return "creditcard.fill"
        case .credit: return "banknote.fill"
        case .insurance: return "shield.fill"
        case .gift: return "gift.fill"
        case .other: return "doc.text.fill"
        }
    }

    public var label: String {
        switch self {
        case .housing: return "Housing"
        case .utilities: return "Utilities"
        case .subscription: return "Subscriptions"
        case .credit: return "Credit"
        case .insurance: return "Insurance"
        case .gift: return "Gifts"
        case .other: return "Other"
        }
    }
}

public enum BillCurrency: String, Codable, CaseIterable, Sendable {
    case usd = "USD"
    case aud = "AUD"
    case eur = "EUR"
    case gbp = "GBP"
    case sgd = "SGD"
    case idr = "IDR"
    case jpy = "JPY"
    case nzd = "NZD"

    public var label: String { rawValue }
}

public struct Bill: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var amount: Double
    public var currencyCode: String
    public var category: BillCategory
    public var recurrence: BillRecurrence
    public var customIntervalDays: Int?
    public var dueDayOfMonth: Int?
    public var nextDueDate: Date
    public var iconName: String
    public var notes: String
    public var isArchived: Bool
    public var createdAt: Date
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        currencyCode: String = BillCurrency.aud.rawValue,
        category: BillCategory = .other,
        recurrence: BillRecurrence = .monthly,
        customIntervalDays: Int? = nil,
        dueDayOfMonth: Int? = nil,
        nextDueDate: Date,
        iconName: String = "",
        notes: String = "",
        isArchived: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.category = category
        self.recurrence = recurrence
        self.customIntervalDays = customIntervalDays
        self.dueDayOfMonth = dueDayOfMonth
        self.nextDueDate = nextDueDate
        self.iconName = iconName.isEmpty ? category.systemImage : iconName
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    public var resolvedIconName: String {
        iconName.isEmpty ? category.systemImage : iconName
    }
}

public struct BillPayment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var billID: UUID
    public var amount: Double
    public var paidAt: Date
    public var note: String

    public init(
        id: UUID = UUID(),
        billID: UUID,
        amount: Double,
        paidAt: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.billID = billID
        self.amount = amount
        self.paidAt = paidAt
        self.note = note
    }
}

public struct BillDueAccent: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum BillDisplayStatus: String, Sendable, CaseIterable, Codable {
    case paid
    case overdue
    case dueSoon
    case partial
    case upcoming

    public var label: String {
        switch self {
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .dueSoon: return "Due soon"
        case .partial: return "Partially paid"
        case .upcoming: return "Upcoming"
        }
    }
}

public struct BillCurrencySummary: Sendable, Identifiable {
    public var currencyCode: String
    public var dueSoonCount: Int
    public var dueSoonAmount: Double
    public var paidThisMonthAmount: Double
    public var dueThisMonthAmount: Double

    public var id: String { currencyCode }

    public init(
        currencyCode: String,
        dueSoonCount: Int = 0,
        dueSoonAmount: Double = 0,
        paidThisMonthAmount: Double = 0,
        dueThisMonthAmount: Double = 0
    ) {
        self.currencyCode = currencyCode
        self.dueSoonCount = dueSoonCount
        self.dueSoonAmount = dueSoonAmount
        self.paidThisMonthAmount = paidThisMonthAmount
        self.dueThisMonthAmount = dueThisMonthAmount
    }
}

public struct BillMonthlySummary: Sendable {
    public var byCurrency: [BillCurrencySummary]

    public var dueSoonCount: Int {
        byCurrency.reduce(0) { $0 + $1.dueSoonCount }
    }

    public init(byCurrency: [BillCurrencySummary] = []) {
        self.byCurrency = byCurrency
    }
}
