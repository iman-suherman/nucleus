import CalendarKit
import Combine
import DatabaseKit
import Foundation
import NucleusCore
import NucleusKit
import SwiftData
import SwiftUI
import SyncKit
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class MobileAppViewModel: ObservableObject {
    @Published var isBootstrapping = true
    @Published var statusMessage = "Starting…"
    @Published var bootstrapStage: MobileBootstrapStage = .starting
    @Published var bootstrapDetailMessage = "Connecting to cloud sync…"
    @Published var errorMessage: String?
    @Published var showWhatsNew = false
    @Published var whatsNewRelease: AppReleaseNotes?
    @Published var showsSettings = false

    let modelContainer: ModelContainer
    let preferencesStore = MobilePreferencesStore.shared
    let settingsSync = MobileSettingsSyncService.shared
    let notesService: NotesMetadataService
    let iCloudSync = ICloudSyncDisplayService.shared
    let meetingReminders = MobileMeetingReminderController.shared

    @Published private(set) var bills: [Bill] = []
    @Published private(set) var billPayments: [BillPayment] = []
    @Published private(set) var calendarEvents: [CalendarEventSummary] = []
    @Published private(set) var isReloadingCalendar = false
    @Published var dashboardQuote: String = DashboardQuotes.currentOrRandom()
    @Published var dashboardQuoteEmojis: String = ""

    private var cloudKitObserver: AnyCancellable?
    private var iCloudSyncObserver: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var dashboardQuoteEmojiTask: Task<Void, Never>?
    private var meetingReminderWatchdogTimer: Timer?
    private var bootstrapTask: Task<Void, Never>?
    private var didBeginStartup = false

    private var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotMode")
    }

    var regularNotes: [NoteDocument] {
        notesService.notes.filter { $0.folder != .passwords }
    }

    var passwordNotes: [NoteDocument] {
        notesService.notes.filter { $0.folder == .passwords }
    }

    init() {
        modelContainer = (try? NucleusDatabase.makeContainer()) ?? {
            fatalError("Failed to create Nucleus database container")
        }()
        notesService = NotesMetadataService(modelContainer: modelContainer)

        iCloudSyncObserver = iCloudSync.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        notesService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settingsSync.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                Task { await self.rescheduleBillReminders() }
            }
            .store(in: &cancellables)

        meetingReminders.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Starts cloud sync immediately and continues bootstrap in the background.
    func beginStartup() {
        guard !didBeginStartup else { return }
        didBeginStartup = true

        normalizeSelectedTab()
        settingsSync.start(modelContainer: modelContainer)
        updateBootstrapStage(.starting, detail: "Registering CloudKit and starting background sync.")

        if isScreenshotMode {
            bootstrapTask = Task { await finishBootstrap() }
            return
        }

        CloudKitSyncService.shared.registerModelContainer(modelContainer)
        CloudKitSyncService.shared.start()
        bootstrapTask = Task { await finishBootstrap() }
    }

    private func finishBootstrap() async {
        isBootstrapping = true

        if isScreenshotMode {
            updateBootstrapStage(.loadingBills, detail: "Preparing dashboard preview.")
            reloadBills()
            notesService.reload()
            refreshDashboardQuoteEmojis()
            isBootstrapping = false
            return
        }

        updateBootstrapStage(.checkingICloud, detail: "Checking iCloud sign-in and sync availability.")
        await iCloudSync.refresh()

        updateBootstrapStage(
            .notifications,
            detail: "Requesting permission for bill due and meeting reminders."
        )
        await requestNotificationPermission()

        observeCloudKitChanges()

        updateBootstrapStage(.loadingBills, detail: "Loading bills and payments from cloud sync.")
        reloadBills()

        updateBootstrapStage(.loadingCalendar, detail: "Loading upcoming calendar events.")
        reloadCalendarEvents()

        updateBootstrapStage(
            .loadingCalendar,
            detail: "Waiting for calendar events imported from your computer."
        )
        await reloadCalendarWaitingForCloudImport()

        updateBootstrapStage(
            .importingNotes,
            detail: "Importing notes and password entries from cloud sync."
        )
        await notesService.reloadWaitingForCloudImport()
        refreshDashboardQuoteEmojis()

        updateBootstrapStage(
            .schedulingReminders,
            detail: "Scheduling bill due and meeting notifications."
        )
        await rescheduleBillReminders()
        await rescheduleMeetingReminders()
        startMeetingReminderWatchdog()

        updateBootstrapStage(.finishing, detail: "Updating badges and preparing your dashboard.")
        await syncAppIconBadge()

        isBootstrapping = false
        await presentWhatsNewIfNeeded()
    }

    private func updateBootstrapStage(_ stage: MobileBootstrapStage, detail: String) {
        bootstrapStage = stage
        bootstrapDetailMessage = detail
        statusMessage = detail
    }

    func dismissWhatsNew() {
        ReleaseNotesLoader.markCurrentVersionSeen()
        showWhatsNew = false
        whatsNewRelease = nil
    }

    func presentCurrentReleaseNotes() async {
        let release = await ReleaseNotesLoader.loadCurrentReleaseAsync()
            ?? AppReleaseNotes(
                version: NucleusAppVersion.current,
                summary: "Nucleus \(NucleusAppVersion.current) is ready.",
                releaseNotes: .init()
            )
        whatsNewRelease = release
        showWhatsNew = true
    }

    private func presentWhatsNewIfNeeded() async {
        guard !isScreenshotMode else { return }
        guard ReleaseNotesLoader.shouldPresentWhatsNew() else { return }
        guard let release = await ReleaseNotesLoader.loadCurrentReleaseAsync() else { return }
        whatsNewRelease = release
        showWhatsNew = true
    }

    var selectedTab: MobileWorkspaceTab {
        get { MobileWorkspaceTab.normalizedForIOS(preferencesStore.preferences.selectedTab) }
        set {
            preferencesStore.update { $0.selectedTab = MobileWorkspaceTab.normalizedForIOS(newValue) }
        }
    }

    func openSettings() {
        showsSettings = true
    }

    func closeSettings() {
        showsSettings = false
    }

    func refreshICloudSync() async {
        await iCloudSync.refresh()
        await notesService.reloadWaitingForCloudImport()
        reloadBills()
        await reloadCalendarWaitingForCloudImport()
        await rescheduleMeetingReminders()
    }

    var activeBills: [Bill] {
        BillScheduleCalculator.sortedActiveBillsByDueDate(bills)
    }

    func reloadBills() {
        let context = ModelContext(modelContainer)
        bills = (try? BillRepository.fetchAll(context: context)) ?? []
        billPayments = (try? BillRepository.fetchPayments(context: context)) ?? []
        Task { await syncAppIconBadge() }
    }

    func reloadCalendarEvents() {
        let context = ModelContext(modelContainer)
        calendarEvents = (try? CalendarRepository.fetchUpcoming(context: context)) ?? []
        checkMeetingRemindersDueNow()
    }

    func reloadCalendarWaitingForCloudImport() async {
        isReloadingCalendar = true
        defer { isReloadingCalendar = false }

        reloadCalendarEvents()
        guard calendarEvents.isEmpty, iCloudSync.isSignedIn, !isScreenshotMode else { return }

        for delay in [2.0, 4.0, 8.0] {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            reloadCalendarEvents()
            if !calendarEvents.isEmpty { break }
        }
    }

    func payments(for billID: UUID) -> [BillPayment] {
        billPayments.filter { $0.billID == billID }
    }

    func paymentsForCurrentPeriod(for bill: Bill) -> [BillPayment] {
        BillScheduleCalculator.paymentsForCurrentPeriod(bill: bill, payments: billPayments)
    }

    func remainingAmount(for bill: Bill) -> Double {
        BillScheduleCalculator.remainingAmount(bill: bill, payments: billPayments)
    }

    func billDisplayStatus(for bill: Bill) -> BillDisplayStatus {
        BillScheduleCalculator.displayStatus(bill: bill, payments: billPayments)
    }

    func billMonthlySummary() -> BillMonthlySummary {
        BillScheduleCalculator.monthlySummary(bills: bills, payments: billPayments)
    }

    func billPaymentSummary() -> DashboardBillPaymentSummary {
        DashboardInsightsEngine.billPaymentSummary(
            bills: bills,
            payments: billPayments,
            includeDueDates: false
        )
    }

    /// Active bills with a balance due within the attention window (includes overdue).
    var billsNearlyDueCount: Int {
        BillScheduleCalculator.dueWithinDaysOrOverdueCount(
            bills: bills,
            payments: billPayments
        )
    }

    var meetingsWithinHourCount: Int {
        MobileDashboardCalendarHelpers.meetingsWithinHourBadgeCount(in: calendarEvents)
    }

    func tabBadgeCount(for tab: MobileWorkspaceTab) -> Int {
        switch tab {
        case .bills:
            return billsNearlyDueCount
        case .calendar:
            return meetingsWithinHourCount
        default:
            return 0
        }
    }

    func logBillPayment(billID: UUID, amount: Double, note: String = "") {
        guard var bill = bills.first(where: { $0.id == billID }) else { return }

        let payment = BillPayment(billID: billID, amount: amount, note: note)
        let context = ModelContext(modelContainer)
        try? BillRepository.insertPayment(payment, context: context)

        let remaining = BillScheduleCalculator.remainingAmount(
            bill: bill,
            payments: billPayments + [payment]
        )
        if remaining <= 0.009 {
            bill.nextDueDate = BillScheduleCalculator.advanceDueDate(
                from: bill.nextDueDate,
                recurrence: bill.recurrence,
                customIntervalDays: bill.customIntervalDays
            )
            try? BillRepository.upsert(bill, context: context)
        }

        exportBillsIfNeeded(context: context)
        reloadBills()
        Task { await rescheduleBillReminders() }
    }

    func saveBill(_ bill: Bill) {
        let context = ModelContext(modelContainer)
        try? BillRepository.upsert(bill, context: context)
        exportBillsIfNeeded(context: context)
        reloadBills()
        Task { await rescheduleBillReminders() }
    }

    func deleteBill(id: UUID) {
        let context = ModelContext(modelContainer)
        try? BillRepository.delete(id: id, context: context)
        exportBillsIfNeeded(context: context)
        reloadBills()
        Task { await rescheduleBillReminders() }
    }

    private func exportBillsIfNeeded(context: ModelContext) {
        if NucleusDatabase.usesCloudKitSync {
            try? NucleusDatabase.exportBillsToCloudKit(context: context, force: true)
        }
    }

    func dashboardSnapshot() -> DashboardSnapshot {
        return DashboardInsightsEngine.build(
            unreadMailCount: 0,
            unreadChatCount: 0,
            passwordCount: passwordNotes.count,
            notesCount: regularNotes.count,
            bills: bills,
            payments: billPayments,
            clipboardEntries: [],
            includeCommunicationActivity: false,
            includeClipboardActivity: false
        )
    }

    func refreshDashboardQuoteEmojis() {
        let quote = dashboardQuote
        if let cached = DashboardQuoteEmojiService.cachedEmojis(for: quote) {
            dashboardQuoteEmojis = cached
            return
        }

        dashboardQuoteEmojis = DashboardQuoteEmojiService.keywordEmojis(for: quote)
        dashboardQuoteEmojiTask?.cancel()
        dashboardQuoteEmojiTask = Task {
            let emojis = await DashboardQuoteEmojiService.resolveEmojis(for: quote)
            guard !Task.isCancelled, quote == dashboardQuote else { return }
            dashboardQuoteEmojis = emojis
        }
    }

    func refreshDashboardQuoteForCurrentContext(forceNew: Bool = false) {
        let isHoliday = DashboardPublicHolidayService.shared.isTodayPublicHoliday
        if forceNew {
            dashboardQuote = DashboardQuotes.pickRandom(
                excluding: dashboardQuote,
                isPublicHoliday: isHoliday
            )
            return
        }
        if let refreshed = DashboardQuotes.refreshIfContextChanged(
            excluding: dashboardQuote,
            isPublicHoliday: isHoliday
        ) {
            dashboardQuote = refreshed
        }
    }

    func captureClipboardToNote() async {
        guard let text = ClipboardCaptureService.currentText() else {
            errorMessage = "Clipboard is empty."
            return
        }
        do {
            try await notesService.captureText(text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveNote(_ note: NoteDocument) throws {
        try notesService.saveNote(note)
    }

    func createNote(in folder: NoteFolder) throws -> NoteDocument {
        let note: NoteDocument
        if folder == .passwords {
            let title = "New Entry"
            note = NoteDocument(
                title: title,
                markdown: NotesMarkdown.passwordNoteTemplate(title: title),
                folder: .passwords
            )
        } else {
            note = NoteDocument(
                title: "Untitled",
                markdown: NotesMarkdown.generalNoteTemplate(title: "Untitled"),
                folder: .notes
            )
        }
        try saveNote(note)
        return note
    }

    func deleteNote(_ note: NoteDocument) throws {
        try notesService.deleteNote(note)
    }

    func pushNotificationPreferences(
        emailEnabled: Bool,
        chatEnabled: Bool,
        calendarEnabled: Bool,
        billConfiguration: BillDueReminderConfiguration,
        iCloudKeychainTokenSyncEnabled: Bool
    ) {
        settingsSync.pushNotificationPreferences(
            emailEnabled: emailEnabled,
            chatEnabled: chatEnabled,
            calendarEnabled: calendarEnabled,
            billConfiguration: billConfiguration,
            iCloudKeychainTokenSyncEnabled: iCloudKeychainTokenSyncEnabled
        )
        Task { await rescheduleBillReminders() }
    }

    func rescheduleBillReminders() async {
        let configuration = settingsSync.syncedConfiguration?.billDueReminderConfiguration
            ?? .default
        await MobileBillReminderScheduler.shared.rescheduleBillReminders(
            bills: bills,
            payments: billPayments,
            configuration: configuration
        )
    }

    var dashboardNextUpcomingBirthdays: [CalendarEventSummary] {
        MobileDashboardCalendarHelpers.upcomingBirthdays(
            in: calendarEvents,
            withinDays: MobileDashboardCalendarHelpers.dashboardBirthdayHorizonDays
        )
    }

    var dashboardTodaysBirthdays: [CalendarEventSummary] {
        MobileDashboardCalendarHelpers.todaysBirthdays(in: calendarEvents)
    }

    var dashboardUpcomingBirthdays: [CalendarEventSummary] {
        MobileDashboardCalendarHelpers.upcomingBirthdays(in: calendarEvents)
    }

    var dashboardScheduleEvents: [CalendarEventSummary] {
        MobileDashboardCalendarHelpers.upcomingScheduleEvents(in: calendarEvents)
    }

    var calendarAccountEmails: [String] {
        Array(Set(calendarEvents.map(\.accountEmail).filter { !$0.isEmpty })).sorted()
    }

    func filteredCalendarEvents(accountEmail: String?) -> [CalendarEventSummary] {
        guard let accountEmail, !accountEmail.isEmpty else { return calendarEvents }
        return calendarEvents.filter { $0.accountEmail == accountEmail }
    }

    var dashboardNextMeetingGroup: MeetingReminderPlanner.UpcomingMeetingGroup? {
        MobileDashboardCalendarHelpers.nextMeetingGroup(in: calendarEvents)
    }

    func startMeetingReminderWatchdog() {
        guard !isScreenshotMode else { return }
        meetingReminderWatchdogTimer?.invalidate()
        meetingReminderWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkMeetingRemindersDueNow()
            }
        }
        checkMeetingRemindersDueNow()
    }

    func checkMeetingRemindersDueNow() {
        let enabled = settingsSync.syncedConfiguration?.calendarNotificationsEnabled ?? true
        meetingReminders.checkDueReminders(in: calendarEvents, enabled: enabled)
    }

    func dismissMeetingReminder() {
        meetingReminders.dismissPrompt()
    }

    func joinMeetingFromReminder(_ event: CalendarEventSummary) {
        guard let link = event.meetingLink, let url = URL(string: link) else { return }
#if canImport(UIKit)
        UIApplication.shared.open(url)
#endif
        meetingReminders.dismissPrompt()
    }

    func openCalendarFromMeetingReminder() {
        selectedTab = .calendar
        meetingReminders.dismissPrompt()
    }

    func rescheduleMeetingReminders() async {
        guard settingsSync.syncedConfiguration?.calendarNotificationsEnabled ?? true else { return }
        MeetingReminderScheduler.shared.registerCategories()
        for event in calendarEvents where event.startDate > Date() {
            guard !BirthdayCalendarFormatting.isBirthdayEvent(event) else { continue }
            await MeetingReminderScheduler.shared.scheduleReminders(for: event)
        }
        checkMeetingRemindersDueNow()
    }

    private func normalizeSelectedTab() {
        let normalized = MobileWorkspaceTab.normalizedForIOS(preferencesStore.preferences.selectedTab)
        guard normalized != preferencesStore.preferences.selectedTab else { return }
        preferencesStore.update { $0.selectedTab = normalized }
    }

    private func observeCloudKitChanges() {
        cloudKitObserver = NotificationCenter.default.publisher(for: .nucleusCloudKitDataDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadBills()
                self?.reloadCalendarEvents()
                Task {
                    await self?.iCloudSync.refresh()
                    await self?.notesService.reloadWaitingForCloudImport()
                    await self?.rescheduleBillReminders()
                    await self?.rescheduleMeetingReminders()
                }
            }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    private func syncAppIconBadge() async {
        await MobileAppIconBadgeService.shared.syncBillDueCount(billsNearlyDueCount)
    }
}
