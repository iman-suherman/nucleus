import Foundation

public struct DashboardUpcomingBill: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public var name: String
    public var dueDate: Date
    public var amountDue: Double
    public var currencyCode: String
    public var category: BillCategory
    public var status: BillDisplayStatus

    public init(
        id: UUID,
        name: String,
        dueDate: Date,
        amountDue: Double,
        currencyCode: String = BillCurrency.aud.rawValue,
        category: BillCategory = .other,
        status: BillDisplayStatus
    ) {
        self.id = id
        self.name = name
        self.dueDate = dueDate
        self.amountDue = amountDue
        self.currencyCode = currencyCode.uppercased()
        self.category = category
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, dueDate, amountDue, currencyCode, category, status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        amountDue = try container.decode(Double.self, forKey: .amountDue)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        category = try container.decodeIfPresent(BillCategory.self, forKey: .category) ?? .other
        status = try container.decode(BillDisplayStatus.self, forKey: .status)
    }
}

public struct DashboardBillPaymentSummaryGroup: Identifiable, Sendable, Equatable, Codable {
    public var category: BillCategory
    public var currencyCode: String
    public var totalAmount: Double
    public var billCount: Int
    public var earliestDueDate: Date
    public var latestDueDate: Date

    public var id: String { "\(category.rawValue)-\(currencyCode)" }

    public init(
        category: BillCategory,
        currencyCode: String,
        totalAmount: Double,
        billCount: Int,
        earliestDueDate: Date,
        latestDueDate: Date
    ) {
        self.category = category
        self.currencyCode = currencyCode.uppercased()
        self.totalAmount = totalAmount
        self.billCount = billCount
        self.earliestDueDate = earliestDueDate
        self.latestDueDate = latestDueDate
    }
}

public struct DashboardBillPaymentSummary: Sendable, Equatable, Codable {
    public var groups: [DashboardBillPaymentSummaryGroup]
    public var preparationNotes: String

    public init(groups: [DashboardBillPaymentSummaryGroup], preparationNotes: String) {
        self.groups = groups
        self.preparationNotes = preparationNotes
    }
}

public struct ClipboardProductivityBucket: Identifiable, Sendable, Equatable, Codable {
    public var id: String { category.rawValue }
    public var category: ClipboardProductivityCategory
    public var count: Int

    public init(category: ClipboardProductivityCategory, count: Int) {
        self.category = category
        self.count = count
    }
}

public enum ClipboardProductivityCategory: String, CaseIterable, Sendable, Codable {
    case development = "Development"
    case communication = "Communication"
    case research = "Research"
    case notesAndDrafts = "Notes & drafts"
    case adminText = "Admin & text"
    case dataAndNumbers = "Data & numbers"

    public var systemImage: String {
        switch self {
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .communication: return "bubble.left.and.bubble.right"
        case .research: return "magnifyingglass"
        case .notesAndDrafts: return "note.text"
        case .adminText: return "doc.text"
        case .dataAndNumbers: return "number"
        }
    }
}

public struct DashboardSnapshot: Sendable, Equatable, Codable {
    public var unreadMailCount: Int
    public var unreadChatCount: Int
    public var passwordCount: Int
    public var upcomingBills: [DashboardUpcomingBill]
    public var productivityBuckets: [ClipboardProductivityBucket]
    public var activitySummary: [String]
    public var productivitySummary: String

    public init(
        unreadMailCount: Int,
        unreadChatCount: Int,
        passwordCount: Int,
        upcomingBills: [DashboardUpcomingBill],
        productivityBuckets: [ClipboardProductivityBucket],
        activitySummary: [String],
        productivitySummary: String
    ) {
        self.unreadMailCount = unreadMailCount
        self.unreadChatCount = unreadChatCount
        self.passwordCount = passwordCount
        self.upcomingBills = upcomingBills
        self.productivityBuckets = productivityBuckets
        self.activitySummary = activitySummary
        self.productivitySummary = productivitySummary
    }
}

public enum DashboardInsightsEngine {
    public static func build(
        unreadMailCount: Int,
        unreadChatCount: Int,
        passwordCount: Int,
        notesCount: Int,
        bills: [Bill],
        payments: [BillPayment],
        clipboardEntries: [ClipboardEntry],
        withinDays: Int = 14,
        clipboardLookbackDays: Int = 7,
        includeCommunicationActivity: Bool = true,
        includeClipboardActivity: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DashboardSnapshot {
        let upcoming = upcomingBills(
            bills: bills,
            payments: payments,
            withinDays: withinDays,
            now: now,
            calendar: calendar
        )
        let buckets = productivityBuckets(
            from: clipboardEntries,
            lookbackDays: clipboardLookbackDays,
            now: now,
            calendar: calendar
        )
        let activity = activitySummaryParagraphs(
            unreadMailCount: unreadMailCount,
            unreadChatCount: unreadChatCount,
            passwordCount: passwordCount,
            notesCount: notesCount,
            upcomingBills: upcoming,
            buckets: buckets,
            clipboardCount: recentClipboardCount(
                entries: clipboardEntries,
                lookbackDays: clipboardLookbackDays,
                now: now,
                calendar: calendar
            ),
            includeCommunicationActivity: includeCommunicationActivity,
            includeClipboardActivity: includeClipboardActivity
        )
        let productivity = includeClipboardActivity ? productivityAssessment(from: buckets) : ""

        return DashboardSnapshot(
            unreadMailCount: unreadMailCount,
            unreadChatCount: unreadChatCount,
            passwordCount: passwordCount,
            upcomingBills: upcoming,
            productivityBuckets: buckets,
            activitySummary: activity,
            productivitySummary: productivity
        )
    }

    public static func upcomingBills(
        bills: [Bill],
        payments: [BillPayment],
        withinDays: Int = 14,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DashboardUpcomingBill] {
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: withinDays, to: today) ?? today

        return bills
            .filter { !$0.isArchived }
            .compactMap { bill -> DashboardUpcomingBill? in
                let remaining = BillScheduleCalculator.remainingAmount(
                    bill: bill,
                    payments: payments,
                    calendar: calendar
                )
                guard remaining > 0.009 else { return nil }

                let dueDay = calendar.startOfDay(for: bill.nextDueDate)
                guard dueDay <= horizon else { return nil }

                return DashboardUpcomingBill(
                    id: bill.id,
                    name: bill.name,
                    dueDate: bill.nextDueDate,
                    amountDue: remaining,
                    currencyCode: bill.currencyCode,
                    category: bill.category,
                    status: BillScheduleCalculator.displayStatus(
                        bill: bill,
                        payments: payments,
                        reference: now,
                        calendar: calendar
                    )
                )
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    public static func billPaymentSummary(
        bills: [Bill],
        payments: [BillPayment],
        withinDays: Int = 14,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeDueDates: Bool = true
    ) -> DashboardBillPaymentSummary {
        let upcoming = upcomingBills(
            bills: bills,
            payments: payments,
            withinDays: withinDays,
            now: now,
            calendar: calendar
        )

        var grouped: [String: (category: BillCategory, currencyCode: String, total: Double, count: Int, earliest: Date, latest: Date)] = [:]

        for bill in upcoming {
            let key = "\(bill.category.rawValue)-\(bill.currencyCode)"
            if var existing = grouped[key] {
                existing.total += bill.amountDue
                existing.count += 1
                existing.earliest = min(existing.earliest, bill.dueDate)
                existing.latest = max(existing.latest, bill.dueDate)
                grouped[key] = existing
            } else {
                grouped[key] = (
                    category: bill.category,
                    currencyCode: bill.currencyCode,
                    total: bill.amountDue,
                    count: 1,
                    earliest: bill.dueDate,
                    latest: bill.dueDate
                )
            }
        }

        let groups = grouped.values
            .map {
                DashboardBillPaymentSummaryGroup(
                    category: $0.category,
                    currencyCode: $0.currencyCode,
                    totalAmount: $0.total,
                    billCount: $0.count,
                    earliestDueDate: $0.earliest,
                    latestDueDate: $0.latest
                )
            }
            .sorted {
                if $0.earliestDueDate != $1.earliestDueDate {
                    return $0.earliestDueDate < $1.earliestDueDate
                }
                if $0.category.rawValue != $1.category.rawValue {
                    return $0.category.rawValue < $1.category.rawValue
                }
                return $0.currencyCode < $1.currencyCode
            }

        return DashboardBillPaymentSummary(
            groups: groups,
            preparationNotes: billPreparationNarrative(
                groups: groups,
                now: now,
                calendar: calendar,
                includeDueDates: includeDueDates
            )
        )
    }

    public static func dueWindowDisplayLabel(
        from earliest: Date,
        to latest: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let datePhrase = dueWindowDatePhrase(from: earliest, to: latest, calendar: calendar)
        let relativePhrase = dueWindowRelativePhrase(from: earliest, to: latest, now: now, calendar: calendar)
        return "\(datePhrase) · \(relativePhrase)"
    }

    public static func dueWindowRelativePhrase(
        from earliest: Date,
        to latest: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let start = calendar.startOfDay(for: earliest)
        let end = calendar.startOfDay(for: latest)
        if start == end {
            return BillScheduleCalculator.dueCountdown(for: earliest, from: now, calendar: calendar)
        }

        let minDays = BillScheduleCalculator.daysUntilDue(for: earliest, from: now, calendar: calendar)
        let maxDays = BillScheduleCalculator.daysUntilDue(for: latest, from: now, calendar: calendar)

        if minDays >= 0 && maxDays >= 0 {
            if minDays == maxDays {
                return BillScheduleCalculator.dueCountdown(for: earliest, from: now, calendar: calendar)
            }
            if minDays == 1 && maxDays == 1 {
                return "Due tomorrow"
            }
            return "Due in \(minDays)–\(maxDays) days"
        }

        if minDays < 0 && maxDays < 0 {
            if minDays == maxDays {
                return BillScheduleCalculator.dueCountdown(for: earliest, from: now, calendar: calendar)
            }
            return "Overdue by \(abs(minDays))–\(abs(maxDays)) days"
        }

        let earliestPhrase = BillScheduleCalculator.dueCountdown(for: earliest, from: now, calendar: calendar)
        let latestPhrase = BillScheduleCalculator.dueCountdown(for: latest, from: now, calendar: calendar)
        return "\(earliestPhrase)–\(latestPhrase)"
    }

    public static func billPreparationNarrative(
        groups: [DashboardBillPaymentSummaryGroup],
        now: Date = Date(),
        calendar: Calendar = .current,
        includeDueDates: Bool = true
    ) -> String {
        guard !groups.isEmpty else {
            return "You're all set — no payments to prepare for in the next two weeks."
        }

        let sentences = groups.map { group -> String in
            let amount = NucleusFormatters.currencyString(group.totalAmount, currencyCode: group.currencyCode)
            let duePhrase = dueWindowPhrase(
                from: group.earliestDueDate,
                to: group.latestDueDate,
                now: now,
                calendar: calendar,
                includeDueDates: includeDueDates
            )
            let billPhrase = group.billCount == 1 ? "1 bill" : "\(group.billCount) bills"
            return "Prepare \(amount) for \(group.category.label.lowercased()) (\(billPhrase) due \(duePhrase))."
        }

        if sentences.count == 1 {
            return sentences[0]
        }

        return "Payment prep for the next two weeks: " + sentences.joined(separator: " ")
    }

    private static func dueWindowPhrase(
        from earliest: Date,
        to latest: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeDueDates: Bool = true
    ) -> String {
        if includeDueDates {
            return dueWindowDisplayLabel(from: earliest, to: latest, now: now, calendar: calendar)
        }
        return dueWindowRelativePhrase(from: earliest, to: latest, now: now, calendar: calendar)
    }

    private static func dueWindowDatePhrase(from earliest: Date, to latest: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: earliest)
        let end = calendar.startOfDay(for: latest)
        if start == end {
            return NucleusFormatters.dayHeader.string(from: earliest)
        }
        return "\(NucleusFormatters.dayHeader.string(from: earliest))–\(NucleusFormatters.dayHeader.string(from: latest))"
    }

    public static func productivityBuckets(
        from entries: [ClipboardEntry],
        lookbackDays: Int = 7,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardProductivityBucket] {
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let recent = entries.filter { $0.capturedAt >= cutoff }

        var counts = Dictionary(
            uniqueKeysWithValues: ClipboardProductivityCategory.allCases.map { ($0, 0) }
        )

        for entry in recent {
            let category = categorize(entry)
            counts[category, default: 0] += 1
        }

        return ClipboardProductivityCategory.allCases.map {
            ClipboardProductivityBucket(category: $0, count: counts[$0, default: 0])
        }
    }

    public static func categorize(_ entry: ClipboardEntry) -> ClipboardProductivityCategory {
        let tags = Set(entry.tags.map { $0.lowercased() })
        let contentType = entry.contentType.lowercased()
        let content = entry.content

        if tags.contains("code")
            || tags.contains("docker")
            || tags.contains("kubernetes")
            || tags.contains("terraform")
            || contentType == "command"
            || contentType == "code" {
            return .development
        }

        if tags.contains("meeting") || tags.contains("url") || contentType == "url" {
            return .communication
        }

        if tags.contains("github") || tags.contains("jira") {
            return .research
        }

        if tags.contains("password") || contentType == "note" {
            return .notesAndDrafts
        }

        if content.contains("/") || content.contains("\\") || content.hasPrefix("~/") {
            return .adminText
        }

        if trimmedLooksNumeric(entry.content) {
            return .dataAndNumbers
        }

        if entry.content.count <= 120 {
            return .notesAndDrafts
        }

        return .adminText
    }

    private static func trimmedLooksNumeric(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,+-$€£¥% ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func recentClipboardCount(
        entries: [ClipboardEntry],
        lookbackDays: Int,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        return entries.filter { $0.capturedAt >= cutoff }.count
    }

    private static func activitySummaryParagraphs(
        unreadMailCount: Int,
        unreadChatCount: Int,
        passwordCount: Int,
        notesCount: Int,
        upcomingBills: [DashboardUpcomingBill],
        buckets: [ClipboardProductivityBucket],
        clipboardCount: Int,
        includeCommunicationActivity: Bool = true,
        includeClipboardActivity: Bool = true
    ) -> [String] {
        var openingParts: [String] = []

        if includeCommunicationActivity {
            if unreadMailCount == 0 {
                openingParts.append("Your inbox is clear right now.")
            } else {
                openingParts.append(
                    "You have \(unreadMailCount) unread email\(unreadMailCount == 1 ? "" : "s") waiting for attention."
                )
            }
        }

        if upcomingBills.isEmpty {
            openingParts.append(includeCommunicationActivity
                ? "No bills are due in the next two weeks."
                : "no bills due in the next two weeks")
        } else {
            let billPhrase = upcomingBills.count == 1 ? "1 upcoming bill" : "\(upcomingBills.count) upcoming bills"
            var totalsByCurrency: [String: Double] = [:]
            for bill in upcomingBills {
                totalsByCurrency[bill.currencyCode, default: 0] += bill.amountDue
            }
            let amountPhrase = totalsByCurrency.keys.sorted().map { code in
                NucleusFormatters.currencyString(totalsByCurrency[code, default: 0], currencyCode: code)
            }.joined(separator: ", ")
            openingParts.append(
                includeCommunicationActivity
                    ? "\(billPhrase) are due soon with \(amountPhrase) still outstanding."
                    : "\(billPhrase) due soon with \(amountPhrase) still outstanding"
            )
        }

        let passwordPhrase = passwordCount == 1
            ? (includeCommunicationActivity ? "1 password is stored" : "1 password stored")
            : (includeCommunicationActivity ? "\(passwordCount) passwords are stored" : "\(passwordCount) passwords stored")
        openingParts.append("\(passwordPhrase) securely in Nucleus.")

        let paragraphOne: String
        if includeCommunicationActivity {
            paragraphOne = openingParts.joined(separator: " ")
        } else {
            paragraphOne = "You have \(openingParts.joined(separator: ", and "))"
        }

        var focusParts: [String] = []
        if includeClipboardActivity {
            if let dominant = buckets.max(by: { $0.count < $1.count }), dominant.count > 0, clipboardCount > 0 {
                focusParts.append(
                    "Over the last week, most of your clipboard activity falls under \(dominant.category.rawValue.lowercased()) work (\(dominant.count) capture\(dominant.count == 1 ? "" : "s"))."
                )
            } else if clipboardCount == 0 {
                focusParts.append("Clipboard activity has been quiet this week, so Nucleus has less signal about your day-to-day focus.")
            } else {
                focusParts.append("Your clipboard captures this week are spread across several kinds of work.")
            }
        }

        if notesCount > 0 {
            focusParts.append("You maintain \(notesCount) note\(notesCount == 1 ? "" : "s") across your knowledge base.")
        }

        if focusParts.isEmpty {
            return [paragraphOne]
        }

        let paragraphTwo = focusParts.joined(separator: " ")

        return [paragraphOne, paragraphTwo]
    }

    private static func productivityAssessment(from buckets: [ClipboardProductivityBucket]) -> String {
        let total = buckets.reduce(0) { $0 + $1.count }
        guard total > 0 else {
            return "Productivity profile: quiet week. Capture more clipboard history to see how your work patterns evolve."
        }

        let sorted = buckets.sorted { $0.count > $1.count }
        guard let top = sorted.first else { return "" }

        let topShare = Double(top.count) / Double(total)
        let activeCategories = buckets.filter { $0.count > 0 }.count

        if topShare >= 0.55 {
            switch top.category {
            case .development:
                return "Productivity profile: builder mode. Your clipboard history points to deep technical work with long stretches of code, commands, and tooling."
            case .communication:
                return "Productivity profile: connector mode. Links, meetings, and messaging dominate your captures, suggesting a collaboration-heavy rhythm."
            case .research:
                return "Productivity profile: explorer mode. Issue trackers and reference material show up often, which fits investigation and planning work."
            case .notesAndDrafts:
                return "Productivity profile: note-taking mode. Short captures and draft text dominate your clipboard history."
            case .adminText:
                return "Productivity profile: admin mode. Paths, documents, and general text make up most of your captures."
            case .dataAndNumbers:
                return "Productivity profile: data mode. Numbers, amounts, and structured values appear frequently in your clipboard."
            }
        }

        if activeCategories >= 3 {
            return "Productivity profile: multi-threaded. Clipboard activity is balanced across several categories, which can mean context switching between building, communicating, and researching."
        }

        return "Productivity profile: mixed focus. Your captures lean toward \(top.category.rawValue.lowercased()) work while still touching other areas throughout the week."
    }
}

public struct StoredDashboardAnalysis: Sendable, Equatable, Codable {
    public var snapshot: DashboardSnapshot
    public var analyzedAt: Date

    public init(snapshot: DashboardSnapshot, analyzedAt: Date = Date()) {
        self.snapshot = snapshot
        self.analyzedAt = analyzedAt
    }
}

public enum DashboardInsightFormatting {
    public static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public static func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func insightParagraphs(from snapshot: DashboardSnapshot, asOf date: Date) -> [String] {
        var paragraphs = snapshot.activitySummary
        guard !paragraphs.isEmpty else {
            return ["As of \(formattedDate(date)) at \(formattedTime(date)), you have limited activity to report yet."]
        }

        paragraphs[0] = prefaceFirstParagraph(paragraphs[0], asOf: date)
        if !snapshot.productivitySummary.isEmpty {
            paragraphs.append(snapshot.productivitySummary)
        }
        return paragraphs
    }

    private static func prefaceFirstParagraph(_ paragraph: String, asOf date: Date) -> String {
        let preface = "As of \(formattedDate(date)) at \(formattedTime(date)), you have"
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("You have ") {
            let remainder = String(trimmed.dropFirst("You have ".count))
            return "\(preface) \(remainder)"
        }

        if trimmed.hasPrefix("Your inbox and chat are clear") {
            let remainder = trimmed.replacingOccurrences(of: "Your inbox and chat are clear", with: "a clear inbox and chat")
            return "\(preface) \(remainder)"
        }

        return "\(preface) \(trimmed.prefix(1).lowercased())\(trimmed.dropFirst())"
    }
}
