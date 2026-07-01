import Foundation

public struct BillDueReminderConfiguration: Sendable, Equatable {
    public var enabled: Bool
    public var hour: Int
    public var notifySevenDaysBefore: Bool
    public var notifyThreeDaysBefore: Bool
    public var notifyOneDayBefore: Bool
    public var notifyOnDueDate: Bool

    public init(
        enabled: Bool = true,
        hour: Int = 7,
        notifySevenDaysBefore: Bool = true,
        notifyThreeDaysBefore: Bool = true,
        notifyOneDayBefore: Bool = true,
        notifyOnDueDate: Bool = true
    ) {
        self.enabled = enabled
        self.hour = hour
        self.notifySevenDaysBefore = notifySevenDaysBefore
        self.notifyThreeDaysBefore = notifyThreeDaysBefore
        self.notifyOneDayBefore = notifyOneDayBefore
        self.notifyOnDueDate = notifyOnDueDate
    }

    public static let `default` = BillDueReminderConfiguration()
}

public enum BillDueReminderPlanner {
    public struct Reminder: Sendable, Hashable {
        public var bill: Bill
        public var fireDate: Date
        public var kind: Kind
        public var amountDue: Double

        public enum Kind: String, Sendable {
            case sevenDaysBefore
            case threeDaysBefore
            case oneDayBefore
            case dueDate
        }
    }

    public static func reminders(
        bills: [Bill],
        payments: [BillPayment],
        configuration: BillDueReminderConfiguration,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Reminder] {
        guard configuration.enabled else { return [] }

        var results: [Reminder] = []
        let leadTimes: [(Reminder.Kind, Int, Bool)] = [
            (.sevenDaysBefore, 7, configuration.notifySevenDaysBefore),
            (.threeDaysBefore, 3, configuration.notifyThreeDaysBefore),
            (.oneDayBefore, 1, configuration.notifyOneDayBefore),
            (.dueDate, 0, configuration.notifyOnDueDate),
        ]

        for bill in bills where !bill.isArchived {
            let remaining = BillScheduleCalculator.remainingAmount(
                bill: bill,
                payments: payments,
                calendar: calendar
            )
            guard remaining > 0 else { continue }

            guard BillScheduleCalculator.isDueWithinNotificationWindow(
                for: bill.nextDueDate,
                reference: now,
                calendar: calendar
            ) else { continue }

            let dueDate = calendar.startOfDay(for: bill.nextDueDate)
            for (kind, daysBefore, isEnabled) in leadTimes where isEnabled {
                guard let fireDate = fireDate(
                    dueDate: dueDate,
                    daysBefore: daysBefore,
                    hour: configuration.hour,
                    calendar: calendar
                ), fireDate > now else { continue }

                results.append(
                    Reminder(
                        bill: bill,
                        fireDate: fireDate,
                        kind: kind,
                        amountDue: remaining
                    )
                )
            }
        }

        return results
    }

    public static func fireDate(
        dueDate: Date,
        daysBefore: Int,
        hour: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard let reminderDay = calendar.date(byAdding: .day, value: -daysBefore, to: dueDate) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
        components.hour = min(23, max(0, hour))
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    public static func notificationTitle(for reminder: Reminder) -> String {
        switch reminder.kind {
        case .sevenDaysBefore:
            return "Bill due in 7 days"
        case .threeDaysBefore:
            return "Bill due in 3 days"
        case .oneDayBefore:
            return "Bill due tomorrow"
        case .dueDate:
            return "Bill due today"
        }
    }

    public static func notificationBody(for reminder: Reminder) -> String {
        let amount = NucleusFormatters.currencyString(reminder.amountDue)
        return "\(reminder.bill.name) — \(amount) due \(NucleusFormatters.dayHeader.string(from: reminder.bill.nextDueDate))"
    }

    public static func notificationIdentifier(for reminder: Reminder, calendar: Calendar = .current) -> String {
        let dueDay = calendar.startOfDay(for: reminder.bill.nextDueDate)
        let stamp = dueDayStamp(dueDay, calendar: calendar)
        return "bill-\(reminder.bill.id.uuidString)-\(reminder.kind.rawValue)-\(stamp)"
    }

    private static func dueDayStamp(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d%02d%02d", year, month, day)
    }
}
