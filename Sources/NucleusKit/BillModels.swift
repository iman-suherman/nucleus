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
}

public struct Bill: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var amount: Double
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

public enum BillDisplayStatus: String, Sendable, CaseIterable {
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

public struct BillMonthlySummary: Sendable {
    public var dueSoonCount: Int
    public var dueSoonAmount: Double
    public var dueThisMonthCount: Int
    public var dueThisMonthAmount: Double
    public var paidThisMonthCount: Int
    public var paidThisMonthAmount: Double
    public var stillDueThisMonthAmount: Double
    public var expectedIncome: Double

    public var okToSpend: Double {
        expectedIncome - paidThisMonthAmount - stillDueThisMonthAmount
    }

    public init(
        dueSoonCount: Int = 0,
        dueSoonAmount: Double = 0,
        dueThisMonthCount: Int = 0,
        dueThisMonthAmount: Double = 0,
        paidThisMonthCount: Int = 0,
        paidThisMonthAmount: Double = 0,
        stillDueThisMonthAmount: Double = 0,
        expectedIncome: Double = 0
    ) {
        self.dueSoonCount = dueSoonCount
        self.dueSoonAmount = dueSoonAmount
        self.dueThisMonthCount = dueThisMonthCount
        self.dueThisMonthAmount = dueThisMonthAmount
        self.paidThisMonthCount = paidThisMonthCount
        self.paidThisMonthAmount = paidThisMonthAmount
        self.stillDueThisMonthAmount = stillDueThisMonthAmount
        self.expectedIncome = expectedIncome
    }
}
