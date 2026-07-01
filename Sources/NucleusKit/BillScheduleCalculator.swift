import Foundation

public enum BillScheduleCalculator {
    /// Days before due (inclusive) when bills count as needing attention for badges and notifications.
    public static let attentionWindowDays = 3

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
                && calendar.startOfDay(for: payment.paidAt) >= calendar.startOfDay(for: periodStart)
                && calendar.startOfDay(for: payment.paidAt) <= calendar.startOfDay(for: bill.nextDueDate)
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
        let days = daysUntilDue(for: dueDate, from: reference, calendar: calendar)

        if days < 0 {
            return "Overdue by \(abs(days)) day\(abs(days) == 1 ? "" : "s")"
        }
        if days == 0 {
            return "Due today"
        }
        if days == 1 {
            return "Due tomorrow"
        }
        if days < 60 {
            return "Due in \(days) days"
        }
        if days < 365 {
            let months = max(1, (days + 15) / 30)
            return "Due in about \(months) month\(months == 1 ? "" : "s")"
        }
        let years = max(1, days / 365)
        return "Due in about \(years) year\(years == 1 ? "" : "s")"
    }

    public static func daysUntilDue(
        for dueDate: Date,
        from reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: reference)
        let due = calendar.startOfDay(for: dueDate)
        return calendar.dateComponents([.day], from: start, to: due).day ?? 0
    }

    /// Accent colour ramp: calm green when more than 15 days away, green→orange as due date nears, red when overdue.
    public static func dueAccent(
        daysUntilDue: Int,
        isPaid: Bool
    ) -> BillDueAccent {
        if isPaid {
            return BillDueAccent(red: 0.52, green: 0.75, blue: 0.58)
        }
        if daysUntilDue < 0 {
            return BillDueAccent(red: 1.0, green: 0.23, blue: 0.19)
        }
        if daysUntilDue > 15 {
            return BillDueAccent(red: 129.0 / 255.0, green: 201.0 / 255.0, blue: 149.0 / 255.0)
        }

        let progress = Double(daysUntilDue) / 15.0
        let orangeRed = 1.0
        let orangeGreen = 0.58
        let orangeBlue = 0.0
        let greenRed = 129.0 / 255.0
        let greenGreen = 201.0 / 255.0
        let greenBlue = 149.0 / 255.0
        return BillDueAccent(
            red: orangeRed + (greenRed - orangeRed) * progress,
            green: orangeGreen + (greenGreen - orangeGreen) * progress,
            blue: orangeBlue + (greenBlue - orangeBlue) * progress
        )
    }

    public static func dueAccent(
        bill: Bill,
        payments: [BillPayment],
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> BillDueAccent {
        let isPaid = remainingAmount(bill: bill, payments: payments, calendar: calendar) <= 0.009
        let days = daysUntilDue(for: bill.nextDueDate, from: reference, calendar: calendar)
        return dueAccent(daysUntilDue: days, isPaid: isPaid)
    }

    public static func dueCountdownLabel(
        bill: Bill,
        payments: [BillPayment],
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if remainingAmount(bill: bill, payments: payments, calendar: calendar) <= 0.009 {
            return "Paid this period"
        }
        return dueCountdown(for: bill.nextDueDate, from: reference, calendar: calendar)
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
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> BillMonthlySummary {
        let activeBills = bills.filter { !$0.isArchived }
        let monthInterval = calendar.dateInterval(of: .month, for: reference)
        let monthStart = monthInterval?.start ?? reference
        let monthEnd = monthInterval?.end ?? reference
        let today = calendar.startOfDay(for: reference)
        let dueSoonHorizon = calendar.date(byAdding: .day, value: 14, to: today) ?? today

        var buckets: [String: BillCurrencySummary] = [:]

        func bucket(for currencyCode: String) -> BillCurrencySummary {
            if let existing = buckets[currencyCode] { return existing }
            let created = BillCurrencySummary(currencyCode: currencyCode)
            buckets[currencyCode] = created
            return created
        }

        for bill in activeBills {
            let remaining = remainingAmount(bill: bill, payments: payments, calendar: calendar)
            let dueDay = calendar.startOfDay(for: bill.nextDueDate)
            var summary = bucket(for: bill.currencyCode)

            if dueDay <= dueSoonHorizon, remaining > 0.009 {
                summary.dueSoonCount += 1
                summary.dueSoonAmount += remaining
            }

            if dueDay >= monthStart, dueDay < monthEnd {
                summary.dueThisMonthAmount += remaining
            }

            buckets[bill.currencyCode] = summary
        }

        let monthPayments = payments.filter { payment in
            payment.paidAt >= monthStart && payment.paidAt < monthEnd
        }

        for payment in monthPayments {
            guard let bill = activeBills.first(where: { $0.id == payment.billID }) else { continue }
            var summary = bucket(for: bill.currencyCode)
            summary.paidThisMonthAmount += payment.amount
            buckets[bill.currencyCode] = summary
        }

        let sorted = buckets.values.sorted { $0.currencyCode < $1.currencyCode }
        return BillMonthlySummary(byCurrency: sorted)
    }

    /// Advances nextDueDate for bills whose current period is fully paid.
    public static func reconcileFullyPaidBills(
        bills: inout [Bill],
        payments: [BillPayment],
        calendar: Calendar = .current
    ) {
        for index in bills.indices {
            var bill = bills[index]
            var safety = 0
            while safety < 24 {
                let remaining = remainingAmount(bill: bill, payments: payments, calendar: calendar)
                guard remaining <= 0.009 else { break }
                bill.nextDueDate = advanceDueDate(
                    from: bill.nextDueDate,
                    recurrence: bill.recurrence,
                    customIntervalDays: bill.customIntervalDays,
                    calendar: calendar
                )
                safety += 1
            }
            bills[index] = bill
        }
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

    /// Active bills sorted by next due date (earliest first, overdue bills naturally first).
    public static func sortedActiveBillsByDueDate(
        _ bills: [Bill],
        calendar: Calendar = .current
    ) -> [Bill] {
        bills
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let lhsDue = calendar.startOfDay(for: lhs.nextDueDate)
                let rhsDue = calendar.startOfDay(for: rhs.nextDueDate)
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    /// True when a bill is overdue or due within `withinDays` (inclusive).
    public static func isDueWithinNotificationWindow(
        for dueDate: Date,
        withinDays: Int = attentionWindowDays,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        daysUntilDue(for: dueDate, from: reference, calendar: calendar) <= withinDays
    }

    /// Counts active bills with a remaining balance that are overdue or due within `withinDays` (inclusive).
    public static func dueWithinDaysOrOverdueCount(
        bills: [Bill],
        payments: [BillPayment],
        withinDays: Int = attentionWindowDays,
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
