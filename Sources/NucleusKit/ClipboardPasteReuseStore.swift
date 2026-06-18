import Foundation

public struct ClipboardPasteReuseEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let entryID: UUID
    public let contentType: String
    public let sourceApplication: String
    public let categoryRawValue: String
    public let reusedAt: Date

    public init(
        id: UUID = UUID(),
        entryID: UUID,
        contentType: String,
        sourceApplication: String,
        category: ClipboardProductivityCategory,
        reusedAt: Date = Date()
    ) {
        self.id = id
        self.entryID = entryID
        self.contentType = contentType
        self.sourceApplication = sourceApplication
        self.categoryRawValue = category.rawValue
        self.reusedAt = reusedAt
    }

    public var category: ClipboardProductivityCategory? {
        ClipboardProductivityCategory(rawValue: categoryRawValue)
    }
}

public enum ClipboardPasteReuseStore {
    public static let userDefaultsKey = "nucleus.clipboard.pasteReuseEvents"
    public static let retentionDays = 7

    public static func record(entry: ClipboardEntry, at date: Date = Date()) {
        let category = DashboardInsightsEngine.categorize(entry)
        let event = ClipboardPasteReuseEvent(
            entryID: entry.id,
            contentType: entry.contentType,
            sourceApplication: entry.sourceApplication,
            category: category,
            reusedAt: date
        )
        var events = loadEvents()
        events.insert(event, at: 0)
        events = prune(events, now: date)
        saveEvents(events)
    }

    public static func loadEvents(now: Date = Date(), calendar: Calendar = .current) -> [ClipboardPasteReuseEvent] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let events = try? JSONDecoder().decode([ClipboardPasteReuseEvent].self, from: data) else {
            return []
        }
        let pruned = prune(events, now: now, calendar: calendar)
        if pruned.count != events.count {
            saveEvents(pruned)
        }
        return pruned
    }

    public static func retentionCutoff(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: now)) ?? now
    }

    private static func prune(
        _ events: [ClipboardPasteReuseEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardPasteReuseEvent] {
        let cutoff = retentionCutoff(from: now, calendar: calendar)
        return events.filter { $0.reusedAt >= cutoff }
    }

    public static func todayEvents(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardPasteReuseEvent] {
        loadEvents().filter { calendar.isDate($0.reusedAt, inSameDayAs: now) }
    }

    public static func categoryBreakdown(
        from events: [ClipboardPasteReuseEvent]
    ) -> [(category: ClipboardProductivityCategory, count: Int, percentage: Int)] {
        guard !events.isEmpty else { return [] }

        var counts: [ClipboardProductivityCategory: Int] = [:]
        for event in events {
            guard let category = event.category else { continue }
            counts[category, default: 0] += 1
        }

        let total = max(events.count, 1)
        return counts
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, count: $0.value, percentage: Int((Double($0.value) / Double(total)) * 100)) }
    }

    public static func keyProductivityHighlight(
        from events: [ClipboardPasteReuseEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard !events.isEmpty else { return nil }

        let breakdown = categoryBreakdown(from: events)
        guard let top = breakdown.first else { return nil }

        let reuseCount = events.count
        let uniqueEntries = Set(events.map(\.entryID)).count

        if top.percentage >= 50 {
            return "Key productivity: \(top.count) of \(reuseCount) ⇧⌘V reuses (\(top.percentage)%) were \(top.category.rawValue.lowercased()) — this is what you recycle most from clipboard history."
        }

        if breakdown.count >= 2 {
            let mix = breakdown.prefix(3)
                .map { "\($0.percentage)% \($0.category.rawValue.lowercased())" }
                .joined(separator: ", ")
            return "Key productivity: \(reuseCount) ⇧⌘V reuses today across \(uniqueEntries) clips — mostly \(mix)."
        }

        return "Key productivity: you reused clipboard history \(reuseCount) time\(reuseCount == 1 ? "" : "s") today via ⇧⌘V, mainly \(top.category.rawValue.lowercased())."
    }

    private static func saveEvents(_ events: [ClipboardPasteReuseEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
