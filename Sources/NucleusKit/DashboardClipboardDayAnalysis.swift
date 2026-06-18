import Foundation

public struct DashboardClipboardWorkGroup: Sendable, Equatable, Codable, Identifiable {
    public var category: ClipboardProductivityCategory
    public var captureCount: Int
    public var workLabel: String
    public var tasks: [String]

    public var id: String { category.rawValue }

    public init(
        category: ClipboardProductivityCategory,
        captureCount: Int,
        workLabel: String,
        tasks: [String]
    ) {
        self.category = category
        self.captureCount = captureCount
        self.workLabel = workLabel
        self.tasks = tasks
    }
}

public struct DashboardClipboardDayAnalysis: Sendable, Equatable, Codable {
    public var daySummary: String
    public var keyProductivityHighlight: String?
    public var behaviorInsights: [String]
    public var improvementSuggestions: [String]
    public var suggestedActions: [String]
    public var workGroups: [DashboardClipboardWorkGroup]
    public var todayCaptureCount: Int
    public var analyzedAt: Date

    public init(
        daySummary: String,
        keyProductivityHighlight: String? = nil,
        behaviorInsights: [String] = [],
        improvementSuggestions: [String] = [],
        suggestedActions: [String],
        workGroups: [DashboardClipboardWorkGroup] = [],
        todayCaptureCount: Int,
        analyzedAt: Date = Date()
    ) {
        self.daySummary = daySummary
        self.keyProductivityHighlight = keyProductivityHighlight
        self.behaviorInsights = behaviorInsights
        self.improvementSuggestions = improvementSuggestions
        self.suggestedActions = suggestedActions
        self.workGroups = workGroups
        self.todayCaptureCount = todayCaptureCount
        self.analyzedAt = analyzedAt
    }
}

public enum DashboardClipboardDigestBuilder {
    public static let maxEntriesInPrompt = 24
    public static let maxPreviewLength = 96

    public static func todayEntries(
        from entries: [ClipboardEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardEntry] {
        entries
            .filter { calendar.isDate($0.capturedAt, inSameDayAs: now) }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    public static func sanitizedPreview(for entry: ClipboardEntry, maxLength: Int = maxPreviewLength) -> String {
        let tags = Set(entry.tags.map { $0.lowercased() })
        if tags.contains("password") || entry.contentType.lowercased() == "password" {
            return "[redacted credential]"
        }

        var preview = entry.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        while preview.contains("  ") {
            preview = preview.replacingOccurrences(of: "  ", with: " ")
        }

        if preview.count > maxLength {
            preview = String(preview.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }

        return preview.isEmpty ? "[empty capture]" : preview
    }

    public static func isSensitiveCapture(_ entry: ClipboardEntry) -> Bool {
        let tags = Set(entry.tags.map { $0.lowercased() })
        if tags.contains("password") || entry.contentType.lowercased() == "password" {
            return true
        }
        let preview = sanitizedPreview(for: entry, maxLength: 32)
        return preview == "[redacted credential]"
    }

    public static func displayExample(from entries: [ClipboardEntry], maxLength: Int = 48) -> String? {
        for entry in entries {
            guard !isSensitiveCapture(entry) else { continue }
            let preview = sanitizedPreview(for: entry, maxLength: maxLength)
            guard preview != "[empty capture]", preview.count >= 8 else { continue }
            return preview
        }
        return nil
    }

    public static func buildPromptContext(
        entries: [ClipboardEntry],
        snapshot: DashboardSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let today = todayEntries(from: entries, now: now, calendar: calendar)
        let dateLabel = DashboardInsightFormatting.formattedDate(now)
        let timeLabel = DashboardInsightFormatting.formattedTime(now)

        var lines: [String] = [
            "Today: \(dateLabel) at \(timeLabel)",
            "Clipboard captures today: \(today.count)",
        ]

        let bucketSummary = snapshot.productivityBuckets
            .filter { $0.count > 0 }
            .map { "\($0.category.rawValue): \($0.count)" }
            .joined(separator: ", ")

        if bucketSummary.isEmpty {
            lines.append("Productivity breakdown (last 7 days): none yet")
        } else {
            lines.append("Productivity breakdown (last 7 days): \(bucketSummary)")
        }

        lines.append("")
        lines.append("Workspace context:")
        lines.append("- Unread emails: \(snapshot.unreadMailCount)")
        lines.append("- Unread chat messages: \(snapshot.unreadChatCount)")
        lines.append("- Saved passwords: \(snapshot.passwordCount)")

        if snapshot.upcomingBills.isEmpty {
            lines.append("- Bills due soon: none")
        } else {
            let billLines = snapshot.upcomingBills.prefix(4).map { bill in
                let amount = NucleusFormatters.currencyString(bill.amountDue, currencyCode: bill.currencyCode)
                let dueLabel = DashboardInsightsEngine.dueWindowDisplayLabel(
                    from: bill.dueDate,
                    to: bill.dueDate,
                    now: now,
                    calendar: calendar
                )
                return "\(bill.name) (\(amount), \(dueLabel))"
            }
            lines.append("- Bills due soon: \(billLines.joined(separator: "; "))")
        }

        if !today.isEmpty {
            lines.append("")
            let pasteReuseToday = ClipboardPasteReuseStore.todayEvents(now: now, calendar: calendar)
            if !pasteReuseToday.isEmpty {
                let reuseBreakdown = ClipboardPasteReuseStore.categoryBreakdown(from: pasteReuseToday)
                    .prefix(4)
                    .map { "\($0.category.rawValue): \($0.count) reuses" }
                    .joined(separator: ", ")
                lines.append("Clipboard history reuses today (⇧⌘V): \(pasteReuseToday.count) (\(reuseBreakdown))")
                if let highlight = ClipboardPasteReuseStore.keyProductivityHighlight(from: pasteReuseToday, now: now, calendar: calendar) {
                    lines.append("Key productivity: \(highlight)")
                }
                lines.append("")
            }

            let workGroups = DashboardClipboardDayAnalysisEngine.inferWorkGroups(from: entries, now: now, calendar: calendar)
            if !workGroups.isEmpty {
                lines.append("Inferred work categories from today's clipboard:")
                for group in workGroups {
                    lines.append("- \(group.category.rawValue) (\(group.captureCount)): \(group.workLabel)")
                    for task in group.tasks.prefix(3) {
                        lines.append("  • \(task)")
                    }
                }
                lines.append("")
            }

            lines.append("Today's clipboard captures (newest first, sensitive content redacted):")
            for (index, entry) in today.prefix(maxEntriesInPrompt).enumerated() {
                let time = NucleusFormatters.time.string(from: entry.capturedAt)
                let category = DashboardInsightsEngine.categorize(entry).rawValue
                let source = entry.sourceApplication.trimmingCharacters(in: .whitespacesAndNewlines)
                let sourceLabel = source.isEmpty ? "Unknown app" : source
                let preview = sanitizedPreview(for: entry)
                lines.append("\(index + 1). \(time) from \(sourceLabel) [\(category)]: \(preview)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public static func digestFingerprint(
        entries: [ClipboardEntry],
        snapshot: DashboardSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let today = todayEntries(from: entries, now: now, calendar: calendar)
        let dayToken = calendar.startOfDay(for: now).timeIntervalSince1970
        let captureToken = today.prefix(12).map { "\($0.id.uuidString)|\($0.capturedAt.timeIntervalSince1970)" }.joined(separator: ";")
        return [
            String(dayToken),
            String(today.count),
            captureToken,
            String(ClipboardPasteReuseStore.todayEvents(now: now, calendar: calendar).count),
            String(snapshot.unreadMailCount),
            String(snapshot.unreadChatCount),
            String(snapshot.upcomingBills.count),
        ].joined(separator: "|")
    }
}

public enum DashboardClipboardDayAnalysisEngine {
    public static func sanitizeDisplayText(_ raw: String) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")

        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"_([^_]+)_"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n", with: " ")

        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }

        text = normalizeVoice(text)

        if text.count > 420 {
            text = String(text.prefix(417)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }

        return text
    }

    public static func nonEmptyDisplayLines(_ lines: [String]) -> [String] {
        lines
            .map(sanitizeDisplayText)
            .filter { line in
                !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    public static func todayCategoryBreakdown(
        from entries: [ClipboardEntry],
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> String {
        let today = DashboardClipboardDigestBuilder.todayEntries(from: entries, now: now, calendar: calendar)
        guard !today.isEmpty else { return "" }

        var counts: [ClipboardProductivityCategory: Int] = [:]
        for entry in today {
            let category = DashboardInsightsEngine.categorize(entry)
            counts[category, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.rawValue < rhs.key.rawValue
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { "\($0.value) \($0.key.rawValue.lowercased())" }
            .joined(separator: " · ")
    }

    public static func parseAIResponse(_ raw: String) -> (
        summary: String,
        insights: [String],
        improvements: [String],
        actions: [String]
    )? {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        let markers: [(key: String, name: String)] = [
            ("SUMMARY:", "summary"),
            ("INSIGHTS:", "insights"),
            ("IMPROVEMENTS:", "improvements"),
            ("ACTIONS:", "actions"),
        ]

        var sections: [String: String] = [:]
        for (index, marker) in markers.enumerated() {
            guard let start = normalized.range(of: marker.key, options: .caseInsensitive)?.upperBound else { continue }
            let end: String.Index
            if index + 1 < markers.count {
                let nextMarker = markers[index + 1].key
                end = normalized.range(of: nextMarker, options: .caseInsensitive)?.lowerBound ?? normalized.endIndex
            } else {
                end = normalized.endIndex
            }
            sections[marker.name] = String(normalized[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let summaryRaw = sections["summary"] {
            let summary = sanitizeDisplayText(summaryRaw)
            let insights = nonEmptyDisplayLines(parseActionLines(from: sections["insights"] ?? ""))
            let improvements = nonEmptyDisplayLines(parseActionLines(from: sections["improvements"] ?? ""))
            let actions = nonEmptyDisplayLines(parseActionLines(from: sections["actions"] ?? ""))
            guard !summary.isEmpty else { return nil }
            return (summary, insights, improvements, actions)
        }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { sanitizeDisplayText($0) }
            .filter { !$0.isEmpty }

        if paragraphs.count >= 2 {
            let summary = paragraphs[0]
            let actions = nonEmptyDisplayLines(parseActionLines(from: paragraphs.dropFirst().joined(separator: "\n")))
            if !summary.isEmpty, !actions.isEmpty {
                return (summary, [], [], actions)
            }
        }

        return nil
    }

    public static func parseAIResponseLegacy(_ raw: String) -> (summary: String, actions: [String])? {
        guard let parsed = parseAIResponse(raw) else { return nil }
        let actions = parsed.actions.isEmpty ? parsed.improvements : parsed.actions
        guard !actions.isEmpty else { return nil }
        return (parsed.summary, actions)
    }

    public static func fallback(
        entries: [ClipboardEntry],
        snapshot: DashboardSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DashboardClipboardDayAnalysis {
        let today = DashboardClipboardDigestBuilder.todayEntries(from: entries, now: now, calendar: calendar)
        let workGroups = inferWorkGroups(from: entries, now: now, calendar: calendar)
        let metrics = analyzeBehavior(today: today, now: now, calendar: calendar)
        let pasteReuseToday = ClipboardPasteReuseStore.todayEvents(now: now, calendar: calendar)
        let keyProductivity = ClipboardPasteReuseStore.keyProductivityHighlight(from: pasteReuseToday, now: now, calendar: calendar)
        let summary = buildFallbackSummary(today: today, workGroups: workGroups, metrics: metrics, pasteReuseToday: pasteReuseToday)
        let insights = buildBehaviorInsights(
            today: today,
            workGroups: workGroups,
            metrics: metrics,
            pasteReuseToday: pasteReuseToday
        )
        let improvements = buildImprovementSuggestions(
            today: today,
            workGroups: workGroups,
            metrics: metrics,
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )
        let actions = buildFallbackActions(
            workGroups: workGroups,
            today: today,
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )
        return DashboardClipboardDayAnalysis(
            daySummary: sanitizeDisplayText(summary),
            keyProductivityHighlight: keyProductivity.map(sanitizeDisplayText),
            behaviorInsights: nonEmptyDisplayLines(insights),
            improvementSuggestions: nonEmptyDisplayLines(improvements),
            suggestedActions: Array(nonEmptyDisplayLines(actions).prefix(5)),
            workGroups: workGroups,
            todayCaptureCount: today.count,
            analyzedAt: now
        )
    }

    struct BehaviorMetrics {
        var categoryShares: [(category: ClipboardProductivityCategory, count: Int, percentage: Int)]
        var sourceApps: [(name: String, count: Int)]
        var activeHours: Int
        var capturesPerHour: Int
        var contextSwitchLevel: String
        var sensitiveCaptureCount: Int
        var dominantPattern: String
    }

    static func analyzeBehavior(
        today: [ClipboardEntry],
        now: Date,
        calendar: Calendar
    ) -> BehaviorMetrics {
        var categoryCounts: [ClipboardProductivityCategory: Int] = [:]
        for entry in today {
            categoryCounts[DashboardInsightsEngine.categorize(entry), default: 0] += 1
        }

        let total = max(today.count, 1)
        let categoryShares = categoryCounts
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, count: $0.value, percentage: Int((Double($0.value) / Double(total)) * 100)) }

        let sourceApps = Dictionary(grouping: today, by: \.sourceApplication)
            .mapValues(\.count)
            .filter { !$0.key.isEmpty && $0.key != "Unknown" }
            .sorted { $0.value > $1.value }
            .map { (name: $0.key, count: $0.value) }

        let hours = Set(today.map { calendar.component(.hour, from: $0.capturedAt) })
        let activeHours = max(hours.count, 1)
        let capturesPerHour = Int(round(Double(today.count) / Double(activeHours)))

        let appCount = sourceApps.count
        let contextSwitchLevel: String
        if appCount >= 6 || categoryShares.count >= 5 {
            contextSwitchLevel = "high"
        } else if appCount >= 4 || categoryShares.count >= 3 {
            contextSwitchLevel = "moderate"
        } else {
            contextSwitchLevel = "low"
        }

        let sensitiveCaptureCount = today.filter { DashboardClipboardDigestBuilder.isSensitiveCapture($0) }.count

        let dominantPattern: String
        if let top = categoryShares.first, top.percentage >= 50 {
            dominantPattern = "focused on \(top.category.rawValue.lowercased())"
        } else if categoryShares.count >= 4 {
            dominantPattern = "spread across many work types"
        } else if let top = categoryShares.first, let second = categoryShares.dropFirst().first {
            dominantPattern = "split between \(top.category.rawValue.lowercased()) and \(second.category.rawValue.lowercased())"
        } else {
            dominantPattern = "mixed activity"
        }

        return BehaviorMetrics(
            categoryShares: categoryShares,
            sourceApps: sourceApps,
            activeHours: activeHours,
            capturesPerHour: capturesPerHour,
            contextSwitchLevel: contextSwitchLevel,
            sensitiveCaptureCount: sensitiveCaptureCount,
            dominantPattern: dominantPattern
        )
    }

    public static func inferWorkGroups(
        from entries: [ClipboardEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DashboardClipboardWorkGroup] {
        let today = DashboardClipboardDigestBuilder.todayEntries(from: entries, now: now, calendar: calendar)
        guard !today.isEmpty else { return [] }

        var grouped: [ClipboardProductivityCategory: [ClipboardEntry]] = [:]
        for entry in today {
            let category = DashboardInsightsEngine.categorize(entry)
            grouped[category, default: []].append(entry)
        }

        return ClipboardProductivityCategory.allCases.compactMap { category in
            guard let categoryEntries = grouped[category], !categoryEntries.isEmpty else { return nil }
            return buildWorkGroup(category: category, entries: categoryEntries)
        }
        .sorted { $0.captureCount > $1.captureCount }
    }

    private static func buildWorkGroup(
        category: ClipboardProductivityCategory,
        entries: [ClipboardEntry]
    ) -> DashboardClipboardWorkGroup {
        let tasks: [String]
        let workLabel: String

        switch category {
        case .development:
            workLabel = "Build & ship"
            tasks = developmentTasks(from: entries)
        case .communication:
            workLabel = "Follow up & respond"
            tasks = communicationTasks(from: entries)
        case .research:
            workLabel = "Review & investigate"
            tasks = researchTasks(from: entries)
        case .notesAndDrafts:
            workLabel = "Capture & document"
            tasks = notesTasks(from: entries)
        case .adminText:
            workLabel = "Organize & share"
            tasks = adminTasks(from: entries)
        case .dataAndNumbers:
            workLabel = "Verify & record"
            tasks = dataTasks(from: entries)
        }

        return DashboardClipboardWorkGroup(
            category: category,
            captureCount: entries.count,
            workLabel: workLabel,
            tasks: Array(tasks.prefix(3))
        )
    }

    private static func developmentTasks(from entries: [ClipboardEntry]) -> [String] {
        var tasks: [String] = []
        let dockerCount = entries.filter { entryMatches($0, tags: ["docker"]) }.count
        let kubeCount = entries.filter { entryMatches($0, tags: ["kubernetes", "kubectl"]) }.count
        let terraformCount = entries.filter { entryMatches($0, tags: ["terraform"]) }.count
        let commandCount = entries.filter { $0.contentType.lowercased() == "command" || $0.contentType.lowercased() == "code" }.count

        if dockerCount > 0 {
            tasks.append(taskLine(
                count: dockerCount,
                verb: "Run or verify",
                noun: "docker workflow step",
                entries: entries.filter { entryMatches($0, tags: ["docker"]) }
            ))
        }
        if kubeCount > 0 {
            tasks.append(taskLine(
                count: kubeCount,
                verb: "Execute",
                noun: "kubernetes command",
                entries: entries.filter { entryMatches($0, tags: ["kubernetes", "kubectl"]) }
            ))
        }
        if terraformCount > 0 {
            tasks.append(taskLine(
                count: terraformCount,
                verb: "Apply",
                noun: "terraform snippet",
                entries: entries.filter { entryMatches($0, tags: ["terraform"]) }
            ))
        }
        if commandCount > dockerCount + kubeCount + terraformCount {
            let remaining = commandCount - dockerCount - kubeCount - terraformCount
            let devEntries = entries.filter {
                $0.contentType.lowercased() == "command" || $0.contentType.lowercased() == "code"
            }
            tasks.append(taskLine(
                count: max(remaining, 1),
                verb: "Batch and run",
                noun: "terminal command",
                entries: devEntries
            ))
        }
        if tasks.isEmpty {
            tasks.append("Finish \(entries.count) development-related capture\(entries.count == 1 ? "" : "s") in one focused session\(formatSourceAppPhrase(topSourceApps(for: entries, limit: 2))).")
        }
        return tasks
    }

    private static func communicationTasks(from entries: [ClipboardEntry]) -> [String] {
        var tasks: [String] = []
        let meetingCount = entries.filter(isMeetingLink).count
        let urlCount = entries.filter(isGenericURL).count
        let apps = topSourceApps(for: entries, limit: 2)

        if meetingCount > 0 {
            tasks.append(taskLine(
                count: meetingCount,
                verb: "Follow up on",
                noun: "meeting link",
                entries: entries.filter(isMeetingLink)
            ))
        }
        if urlCount > meetingCount {
            let linkCount = urlCount - meetingCount
            var line = taskLine(
                count: linkCount,
                verb: "Review and action",
                noun: "shared link",
                entries: entries.filter(isGenericURL)
            )
            if !apps.isEmpty {
                line = String(line.dropLast()) + formatSourceAppPhrase(apps) + "."
            }
            tasks.append(line)
        }
        if tasks.isEmpty {
            tasks.append("Respond to \(entries.count) communication snippet\(entries.count == 1 ? "" : "s")\(formatSourceAppPhrase(apps)).")
        }
        return tasks
    }

    private static func researchTasks(from entries: [ClipboardEntry]) -> [String] {
        var tasks: [String] = []
        let githubCount = entries.filter { $0.content.lowercased().contains("github.com") || entryMatches($0, tags: ["github"]) }.count
        let jiraCount = entries.filter { entryMatches($0, tags: ["jira"]) || $0.content.lowercased().contains("atlassian.net") }.count

        if githubCount > 0 {
            tasks.append(taskLine(count: githubCount, verb: "Review", noun: "GitHub link", entries: entries))
        }
        if jiraCount > 0 {
            tasks.append(taskLine(count: jiraCount, verb: "Update or close", noun: "Jira item", entries: entries))
        }
        if tasks.isEmpty {
            tasks.append(taskLine(count: entries.count, verb: "Investigate", noun: "research snippet", entries: entries))
        }
        return tasks
    }

    private static func notesTasks(from entries: [ClipboardEntry]) -> [String] {
        let apps = topSourceApps(for: entries, limit: 3)
        let appPhrase = formatSourceAppPhrase(apps)
        if entries.count >= 10 {
            return ["Consolidate \(entries.count) draft snippets into 2–3 structured notes\(appPhrase)."]
        }
        return ["Merge \(entries.count) draft snippet\(entries.count == 1 ? "" : "s") into one note\(appPhrase)."]
    }

    private static func adminTasks(from entries: [ClipboardEntry]) -> [String] {
        let pathEntries = entries.filter { looksLikePath($0.content) }
        let apps = topSourceApps(for: entries, limit: 2)
        let appPhrase = formatSourceAppPhrase(apps)
        if pathEntries.count > 0 {
            return ["Organize \(pathEntries.count) copied file or document reference\(pathEntries.count == 1 ? "" : "s") into your project docs\(appPhrase)."]
        }
        return ["Sort \(entries.count) admin text capture\(entries.count == 1 ? "" : "s") into reusable templates\(appPhrase)."]
    }

    private static func dataTasks(from entries: [ClipboardEntry]) -> [String] {
        ["Verify \(entries.count) copied figure\(entries.count == 1 ? "" : "s") against the source before entering them in sheets or payments."]
    }

    private static func taskLine(
        count: Int,
        verb: String,
        noun: String,
        entries: [ClipboardEntry],
        includeExample: Bool = false
    ) -> String {
        let plural = count == 1 ? "" : "s"
        var line = "\(verb) \(count) \(noun)\(plural)"
        if includeExample, let example = DashboardClipboardDigestBuilder.displayExample(from: entries) {
            line += " — e.g. \(example)"
        }
        return line + "."
    }

    private static func formatSourceAppPhrase(_ apps: [String]) -> String {
        guard !apps.isEmpty else { return "" }
        return " — mostly from \(apps.joined(separator: ", "))"
    }

    private static func entryMatches(_ entry: ClipboardEntry, tags: [String]) -> Bool {
        let entryTags = Set(entry.tags.map { $0.lowercased() })
        let loweredTags = Set(tags.map { $0.lowercased() })
        if !entryTags.isDisjoint(with: loweredTags) { return true }
        let content = entry.content.lowercased()
        return tags.contains { content.contains($0.lowercased()) }
    }

    private static func isMeetingLink(_ entry: ClipboardEntry) -> Bool {
        let content = entry.content.lowercased()
        let tags = Set(entry.tags.map { $0.lowercased() })
        return tags.contains("meeting")
            || content.contains("meet.google")
            || content.contains("zoom.us")
            || content.contains("teams.microsoft.com/meet")
    }

    private static func isGenericURL(_ entry: ClipboardEntry) -> Bool {
        entry.contentType.lowercased() == "url"
            || entry.content.lowercased().hasPrefix("http")
            || entry.tags.map { $0.lowercased() }.contains("url")
    }

    private static func looksLikePath(_ content: String) -> Bool {
        content.contains("/") || content.contains("\\") || content.hasPrefix("~/")
    }

    private static func topSourceApps(for entries: [ClipboardEntry], limit: Int) -> [String] {
        Dictionary(grouping: entries, by: \.sourceApplication)
            .mapValues(\.count)
            .filter { !$0.key.isEmpty && $0.key != "Unknown" }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    private static func buildFallbackSummary(
        today: [ClipboardEntry],
        workGroups: [DashboardClipboardWorkGroup],
        metrics: BehaviorMetrics,
        pasteReuseToday: [ClipboardPasteReuseEvent]
    ) -> String {
        guard !today.isEmpty else {
            return "You have no clipboard captures yet today — copy work items from your apps to see productivity analytics here."
        }

        if let highlight = ClipboardPasteReuseStore.keyProductivityHighlight(from: pasteReuseToday) {
            var parts = [highlight]
            if let top = metrics.categoryShares.first {
                parts.append("You also captured \(today.count) new items today — \(top.percentage)% \(top.category.rawValue.lowercased()).")
            }
            return parts.joined(separator: " ")
        }

        guard let top = metrics.categoryShares.first else {
            return "You copied \(today.count) item\(today.count == 1 ? "" : "s") today."
        }

        var parts: [String] = [
            "You captured \(today.count) items today, \(metrics.dominantPattern) — \(top.percentage)% \(top.category.rawValue.lowercased()).",
        ]

        if metrics.sourceApps.count >= 2 {
            let topApps = metrics.sourceApps.prefix(3).map { "\($0.name) (\($0.count))" }.joined(separator: ", ")
            parts.append("Activity flowed through \(metrics.sourceApps.count) apps: \(topApps).")
        }

        if metrics.contextSwitchLevel == "high" {
            parts.append("Your clipboard pattern shows heavy context switching — many small captures instead of fewer, deeper work blocks.")
        } else if metrics.capturesPerHour >= 6 {
            parts.append("You're averaging about \(metrics.capturesPerHour) captures per active hour, which often means reactive copy-paste rather than planned output.")
        }

        return parts.joined(separator: " ")
    }

    private static func buildBehaviorInsights(
        today: [ClipboardEntry],
        workGroups: [DashboardClipboardWorkGroup],
        metrics: BehaviorMetrics,
        pasteReuseToday: [ClipboardPasteReuseEvent]
    ) -> [String] {
        var insights: [String] = []

        if !pasteReuseToday.isEmpty {
            let reuseBreakdown = ClipboardPasteReuseStore.categoryBreakdown(from: pasteReuseToday)
            if let topReuse = reuseBreakdown.first {
                insights.append("\(topReuse.count) of \(pasteReuseToday.count) ⇧⌘V reuses (\(topReuse.percentage)%) were \(topReuse.category.rawValue.lowercased()) — your main recycled work type.")
            }
            let uniqueClips = Set(pasteReuseToday.map(\.entryID)).count
            if pasteReuseToday.count >= 3 {
                insights.append("You reused \(uniqueClips) saved clip\(uniqueClips == 1 ? "" : "s") via ⇧⌘V instead of copying again — clipboard history is part of your workflow.")
            }
        }

        if let top = metrics.categoryShares.first {
            insights.append("\(top.count) of \(today.count) captures (\(top.percentage)%) were \(top.category.rawValue.lowercased()) — your dominant work mode today.")
        }

        if metrics.categoryShares.count >= 3 {
            let breakdown = metrics.categoryShares.prefix(4)
                .map { "\($0.percentage)% \($0.category.rawValue.lowercased())" }
                .joined(separator: ", ")
            insights.append("Category mix: \(breakdown).")
        }

        if !metrics.sourceApps.isEmpty {
            let appBreakdown = metrics.sourceApps.prefix(4)
                .map { "\($0.name): \($0.count)" }
                .joined(separator: ", ")
            insights.append("Top sources: \(appBreakdown) across \(metrics.activeHours) active hour\(metrics.activeHours == 1 ? "" : "s").")
        }

        switch metrics.contextSwitchLevel {
        case "high":
            insights.append("Context switching is high — \(metrics.sourceApps.count) apps and \(workGroups.count) work categories competed for attention.")
        case "moderate":
            insights.append("Moderate context switching — you moved between \(workGroups.count) work types and \(metrics.sourceApps.count) apps.")
        default:
            if today.count >= 5 {
                insights.append("Focus pattern is relatively tight — most captures cluster in a small set of apps and categories.")
            }
        }

        if metrics.sensitiveCaptureCount > 0 {
            insights.append("\(metrics.sensitiveCaptureCount) sensitive capture\(metrics.sensitiveCaptureCount == 1 ? "" : "s") detected — avoid using clipboard for credentials.")
        }

        if let notesGroup = workGroups.first(where: { $0.category == .notesAndDrafts }), notesGroup.captureCount >= 10 {
            insights.append("\(notesGroup.captureCount) draft snippets suggest note fragmentation — material is being copied but not yet consolidated.")
        }

        return Array(insights.prefix(5))
    }

    private static func buildImprovementSuggestions(
        today: [ClipboardEntry],
        workGroups: [DashboardClipboardWorkGroup],
        metrics: BehaviorMetrics,
        snapshot: DashboardSnapshot,
        now: Date,
        calendar: Calendar
    ) -> [String] {
        var suggestions: [String] = []

        if let notesGroup = workGroups.first(where: { $0.category == .notesAndDrafts }), notesGroup.captureCount >= 8 {
            suggestions.append("Block 25 minutes to merge \(notesGroup.captureCount) draft snippets into 2–3 permanent notes — this is your largest unfinished queue.")
        }

        let pasteReuseToday = ClipboardPasteReuseStore.todayEvents(now: now, calendar: calendar)
        if let topReuse = ClipboardPasteReuseStore.categoryBreakdown(from: pasteReuseToday).first, topReuse.count >= 3 {
            suggestions.append("Pin your top ⇧⌘V reuse category (\(topReuse.category.rawValue.lowercased())) clips so your most recycled material stays one shortcut away.")
        }

        if metrics.contextSwitchLevel == "high" {
            suggestions.append("Reduce context switches: pick one category (e.g. development or communication) and process all related captures in a single 30-minute block.")
        }

        if metrics.capturesPerHour >= 8 {
            suggestions.append("Slow the capture pace — aim for under 5 clipboard copies per hour by keeping reference material in one note instead of re-copying.")
        }

        if let commGroup = workGroups.first(where: { $0.category == .communication }), commGroup.captureCount >= 3 {
            suggestions.append("Process \(commGroup.captureCount) shared links in one pass — open, action, and close each before switching apps.")
        }

        if let devGroup = workGroups.first(where: { $0.category == .development }), devGroup.captureCount >= 2 {
            suggestions.append("Batch \(devGroup.captureCount) terminal commands into one shell session instead of copying them one at a time.")
        }

        if metrics.sensitiveCaptureCount > 0 {
            suggestions.append("Stop copying passwords to clipboard — save credentials in Nucleus Passwords and use the menu bar picker instead.")
        }

        if let adminGroup = workGroups.first(where: { $0.category == .adminText }), adminGroup.captureCount >= 5 {
            suggestions.append("Turn \(adminGroup.captureCount) admin text captures into a shared doc or template so you stop re-copying the same references.")
        }

        if suggestions.count < 3, snapshot.unreadMailCount > 0 {
            let target = min(snapshot.unreadMailCount, max(3, snapshot.unreadMailCount / 2))
            suggestions.append("Clear \(target) of \(snapshot.unreadMailCount) unread emails in 20 minutes to reduce link-chasing through clipboard.")
        }

        if suggestions.isEmpty, !today.isEmpty {
            suggestions.append("Review your top category and schedule one 20-minute block to finish its open items before copying anything new.")
        }

        var seen = Set<String>()
        return suggestions.filter { seen.insert($0).inserted }.prefix(5).map { $0 }
    }

    private static func buildFallbackActions(
        workGroups: [DashboardClipboardWorkGroup],
        today: [ClipboardEntry],
        snapshot: DashboardSnapshot,
        now: Date,
        calendar: Calendar
    ) -> [String] {
        var actions = workGroups.flatMap(\.tasks)

        if actions.isEmpty, !today.isEmpty {
            actions.append("Review \(today.count) clipboard capture\(today.count == 1 ? "" : "s") and sort them into notes or tasks.")
        }

        if actions.count < 3, snapshot.unreadMailCount > 0 {
            let target = min(snapshot.unreadMailCount, max(3, snapshot.unreadMailCount / 2))
            actions.append("Spend 20 minutes clearing \(target) of \(snapshot.unreadMailCount) unread emails tied to copied links.")
        }

        var seen = Set<String>()
        return actions.filter { seen.insert($0).inserted }
    }

    private static func normalizeVoice(_ text: String) -> String {
        var normalized = text

        if normalized.hasPrefix("The user ") {
            normalized = "You " + String(normalized.dropFirst("The user ".count))
        } else if normalized.hasPrefix("the user ") {
            normalized = "You " + String(normalized.dropFirst("the user ".count))
        }

        normalized = normalized.replacingOccurrences(of: " their ", with: " your ")
        normalized = normalized.replacingOccurrences(of: " they ", with: " you ")
        normalized = normalized.replacingOccurrences(of: " them ", with: " you ")
        normalized = normalized.replacingOccurrences(of: "themself", with: "yourself")
        normalized = normalized.replacingOccurrences(of: "themselves", with: "yourself")

        if normalized.hasPrefix("You ") {
            let remainder = String(normalized.dropFirst(4))
            if let first = remainder.first, first.isLowercase {
                normalized = "You " + remainder.prefix(1).uppercased() + remainder.dropFirst()
            }
        }

        return normalized
    }

    private static func parseActionLines(from block: String) -> [String] {
        block
            .components(separatedBy: .newlines)
            .map { line in
                var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = trimmed.range(of: #"^\d+[\).\:-]\s*"#, options: .regularExpression) {
                    trimmed.removeSubrange(match)
                }
                trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
                return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty && !isIgnorableParsedLine(line)
            }
    }

    private static func isIgnorableParsedLine(_ line: String) -> Bool {
        let lowered = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
            .lowercased()
        if lowered.isEmpty { return true }
        let sectionHeaders = [
            "suggestions to improve",
            "productivity insights",
            "work from your clipboard",
            "work to do",
            "summary",
            "insights",
            "improvements",
            "actions",
        ]
        return sectionHeaders.contains(lowered)
    }
}
