import Foundation

public enum BillScheduleCalculator {
    public static func initialNextDueDate(
        recurrence: BillRecurrence,
        dueDayOfMonth: Int?,
        anchorDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        switch recurrence {
        case .monthly:
            let day = dueDayOfMonth ?? calendar.component(.day, from: anchorDate)
            return nextMonthlyDue(day: day, after: anchorDate, calendar: calendar)
        case .every30Days, .weekly, .yearly, .customDays:
            return calendar.startOfDay(for: anchorDate)
        }
    }

    public static func advanceDueDate(
        from currentDue: Date,
        recurrence: BillRecurrence,
        customIntervalDays: Int?,
        calendar: Calendar = .current
    ) -> Date {
        switch recurrence {
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: currentDue) ?? currentDue
        case .every30Days:
            return calendar.date(byAdding: .day, value: 30, to: currentDue) ?? currentDue
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: currentDue) ?? currentDue
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: currentDue) ?? currentDue
        case .customDays:
            let days = max(1, customIntervalDays ?? 30)
            return calendar.date(byAdding: .day, value: days, to: currentDue) ?? currentDue
        }
    }

    public static func previousDueDate(
        before nextDue: Date,
        recurrence: BillRecurrence,
        customIntervalDays: Int?,
        calendar: Calendar = .current
    ) -> Date {
        switch recurrence {
        case .monthly:
            return calendar.date(byAdding: .month, value: -1, to: nextDue) ?? nextDue
        case .every30Days:
            return calendar.date(byAdding: .day, value: -30, to: nextDue) ?? nextDue
        case .weekly:
            return calendar.date(byAdding: .day, value: -7, to: nextDue) ?? nextDue
        case .yearly:
            return calendar.date(byAdding: .year, value: -1, to: nextDue) ?? nextDue
        case .customDays:
            let days = max(1, customIntervalDays ?? 30)
            return calendar.date(byAdding: .day, value: -days, to: nextDue) ?? nextDue
        }
    }

    public static func paymentsForCurrentPeriod(
        bill: Bill,
        payments: [BillPayment],
        calendar: Calendar = .current
    ) -> [BillPayment] {
        let periodStart = previousDueDate(
            before: bill.nextDueDate,
            recurrence: bill.recurrence,
            customIntervalDays: bill.customIntervalDays,
            calendar: calendar
        )
        return payments.filter { payment in
            payment.billID == bill.id
                && payment.paidAt >= periodStart
                && payment.paidAt <= bill.nextDueDate
        }
    }

    public static func amountPaidThisPeriod(
        bill: Bill,
        payments: [BillPayment],
        calendar: Calendar = .current
    ) -> Double {
        paymentsForCurrentPeriod(bill: bill, payments: payments, calendar: calendar)
            .reduce(0) { $0 + $1.amount }
    }

    public static func remainingAmount(
        bill: Bill,
        payments: [BillPayment],
        calendar: Calendar = .current
    ) -> Double {
        max(0, bill.amount - amountPaidThisPeriod(bill: bill, payments: payments, calendar: calendar))
    }

    public static func averagePaymentAmount(
        billID: UUID,
        payments: [BillPayment]
    ) -> Double? {
        let billPayments = payments.filter { $0.billID == billID }
        guard !billPayments.isEmpty else { return nil }
        let total = billPayments.reduce(0) { $0 + $1.amount }
        return total / Double(billPayments.count)
    }

    public static func dueCountdown(for dueDate: Date, from reference: Date = Date(), calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: reference)
        let due = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents([.day], from: start, to: due).day ?? 0

        if days < 0 {
            return "Overdue by \(abs(days)) day\(abs(days) == 1 ? "" : "s")"
        }
        if days == 0 {
            return "Due today"
        }
        if days == 1 {
            return "Due tomorrow"
        }
        if days < 14 {
            return "Due in \(days) days"
        }
        if days < 45 {
            return "Due in about 1 month"
        }
        let months = max(1, days / 30)
        return "Due in about \(months) month\(months == 1 ? "" : "s")"
    }

    public static func progressUntilDue(
        bill: Bill,
        payments: [BillPayment],
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let periodStart = previousDueDate(
            before: bill.nextDueDate,
            recurrence: bill.recurrence,
            customIntervalDays: bill.customIntervalDays,
            calendar: calendar
        )
        let totalInterval = bill.nextDueDate.timeIntervalSince(periodStart)
        guard totalInterval > 0 else { return 1 }

        let elapsed = reference.timeIntervalSince(periodStart)
        let timeProgress = min(1, max(0, elapsed / totalInterval))

        let paid = amountPaidThisPeriod(bill: bill, payments: payments, calendar: calendar)
        let paymentProgress = bill.amount > 0 ? min(1, paid / bill.amount) : 1

        return max(timeProgress, paymentProgress)
    }

    public static func monthlySummary(
        bills: [Bill],
        payments: [BillPayment],
        expectedIncome: Double,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> BillMonthlySummary {
        let activeBills = bills.filter { !$0.isArchived }
        let monthInterval = calendar.dateInterval(of: .month, for: reference)
        let monthStart = monthInterval?.start ?? reference
        let monthEnd = monthInterval?.end ?? reference

        var dueSoonCount = 0
        var dueSoonAmount = 0.0
        var dueThisMonthCount = 0
        var dueThisMonthAmount = 0.0
        var stillDueThisMonthAmount = 0.0

        for bill in activeBills {
            let remaining = remainingAmount(bill: bill, payments: payments, calendar: calendar)
            let due = bill.nextDueDate

            if due >= reference, due <= calendar.date(byAdding: .day, value: 14, to: reference) ?? reference {
                dueSoonCount += 1
                dueSoonAmount += remaining
            }

            if due >= monthStart, due < monthEnd {
                dueThisMonthCount += 1
                dueThisMonthAmount += bill.amount
                stillDueThisMonthAmount += remaining
            }
        }

        let monthPayments = payments.filter { payment in
            payment.paidAt >= monthStart && payment.paidAt < monthEnd
        }
        let paidBillIDs = Set(monthPayments.map(\.billID))

        return BillMonthlySummary(
            dueSoonCount: dueSoonCount,
            dueSoonAmount: dueSoonAmount,
            dueThisMonthCount: dueThisMonthCount,
            dueThisMonthAmount: dueThisMonthAmount,
            paidThisMonthCount: paidBillIDs.count,
            paidThisMonthAmount: monthPayments.reduce(0) { $0 + $1.amount },
            stillDueThisMonthAmount: stillDueThisMonthAmount,
            expectedIncome: expectedIncome
        )
    }

    public static func dueDates(in month: Date, bills: [Bill], calendar: Calendar = .current) -> Set<DateComponents> {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var dates = Set<DateComponents>()

        for bill in bills where !bill.isArchived {
            let due = calendar.startOfDay(for: bill.nextDueDate)
            if due >= monthInterval.start, due < monthInterval.end {
                dates.insert(calendar.dateComponents([.year, .month, .day], from: due))
            }
        }
        return dates
    }

    /// Counts active bills with a remaining balance that are overdue or due within `withinDays` (inclusive).
    public static func dueWithinDaysOrOverdueCount(
        bills: [Bill],
        payments: [BillPayment],
        withinDays: Int = 3,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: reference)
        let horizon = calendar.date(byAdding: .day, value: withinDays, to: today) ?? today

        return bills.reduce(into: 0) { count, bill in
            guard !bill.isArchived else { return }
            guard remainingAmount(bill: bill, payments: payments, calendar: calendar) > 0.009 else { return }

            let dueDay = calendar.startOfDay(for: bill.nextDueDate)
            if dueDay <= horizon {
                count += 1
            }
        }
    }

    public static func displayStatus(
        bill: Bill,
        payments: [BillPayment],
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> BillDisplayStatus {
        let remaining = remainingAmount(bill: bill, payments: payments, calendar: calendar)
        if remaining <= 0.009 {
            return .paid
        }

        let dueDay = calendar.startOfDay(for: bill.nextDueDate)
        let today = calendar.startOfDay(for: reference)
        if dueDay < today {
            return .overdue
        }

        let paid = amountPaidThisPeriod(bill: bill, payments: payments, calendar: calendar)
        if paid > 0.009 {
            return .partial
        }

        if let soon = calendar.date(byAdding: .day, value: 14, to: today), dueDay <= soon {
            return .dueSoon
        }

        return .upcoming
    }

    public static func statusProgress(
        bill: Bill,
        payments: [BillPayment],
        status: BillDisplayStatus,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        switch status {
        case .paid:
            return 1
        case .overdue:
            return 1
        case .partial:
            let paid = amountPaidThisPeriod(bill: bill, payments: payments, calendar: calendar)
            return bill.amount > 0 ? min(1, paid / bill.amount) : 1
        case .dueSoon, .upcoming:
            return progressUntilDue(bill: bill, payments: payments, reference: reference, calendar: calendar)
        }
    }

    private static func nextMonthlyDue(day: Int, after reference: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month], from: reference)
        let year = components.year ?? calendar.component(.year, from: reference)
        let month = components.month ?? calendar.component(.month, from: reference)
        components.day = clampedDay(day, year: year, month: month, calendar: calendar)

        var candidate = calendar.date(from: components) ?? reference
        if candidate <= calendar.startOfDay(for: reference) {
            components.month = (components.month ?? month) + 1
            if components.month == 13 {
                components.month = 1
                components.year = (components.year ?? year) + 1
            }
            let nextYear = components.year ?? year
            let nextMonth = components.month ?? 1
            components.day = clampedDay(day, year: nextYear, month: nextMonth, calendar: calendar)
            candidate = calendar.date(from: components) ?? candidate
        }
        return candidate
    }

    private static func clampedDay(_ day: Int, year: Int, month: Int, calendar: Calendar) -> Int {
        let components = DateComponents(year: year, month: month)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return min(max(day, 1), 28)
        }
        return min(max(day, 1), range.count)
    }
}
