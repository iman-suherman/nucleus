import Combine
import DatabaseKit
import Foundation
import NucleusCore
import NucleusKit
import SwiftData
import SwiftUI
import SyncKit
import UserNotifications

@MainActor
final class MobileAppViewModel: ObservableObject {
    @Published var isBootstrapping = true
    @Published var statusMessage = "Starting…"
    @Published var errorMessage: String?
    @Published var showWhatsNew = false
    @Published var whatsNewRelease: AppReleaseNotes?

    let modelContainer: ModelContainer
    let preferencesStore = MobilePreferencesStore.shared
    let settingsSync = MobileSettingsSyncService.shared
    let notesService: NotesMetadataService
    let iCloudSync = ICloudSyncDisplayService.shared

    @Published private(set) var bills: [Bill] = []
    @Published private(set) var billPayments: [BillPayment] = []
    @Published var dashboardQuote: String = DashboardQuotes.currentOrRandom()
    @Published var dashboardQuoteEmojis: String = ""

    private var cloudKitObserver: AnyCancellable?
    private var iCloudSyncObserver: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var dashboardQuoteEmojiTask: Task<Void, Never>?

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
    }

    func bootstrap() async {
        isBootstrapping = true
        statusMessage = "Connecting to cloud sync…"

        normalizeSelectedTab()
        settingsSync.start(modelContainer: modelContainer)

        if isScreenshotMode {
            reloadBills()
            notesService.reload()
            refreshDashboardQuoteEmojis()
            statusMessage = "Ready"
            isBootstrapping = false
            return
        }

        CloudKitSyncService.shared.registerModelContainer(modelContainer)
        CloudKitSyncService.shared.start()
        await iCloudSync.refresh()
        await requestNotificationPermission()

        observeCloudKitChanges()
        reloadBills()
        await notesService.reloadWaitingForCloudImport()
        refreshDashboardQuoteEmojis()
        await rescheduleBillReminders()
        await syncAppIconBadge()

        statusMessage = "Ready"
        isBootstrapping = false
        await presentWhatsNewIfNeeded()
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

    func refreshICloudSync() async {
        await iCloudSync.refresh()
        await notesService.reloadWaitingForCloudImport()
        reloadBills()
    }

    var activeBills: [Bill] {
        bills.filter { !$0.isArchived }
    }

    func reloadBills() {
        let context = ModelContext(modelContainer)
        bills = (try? BillRepository.fetchAll(context: context)) ?? []
        billPayments = (try? BillRepository.fetchPayments(context: context)) ?? []
        Task { await syncAppIconBadge() }
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

    /// Active bills with a balance due within the next 14 days (includes overdue).
    var billsNearlyDueCount: Int {
        billMonthlySummary().dueSoonCount
    }

    func tabBadgeCount(for tab: MobileWorkspaceTab) -> Int {
        switch tab {
        case .bills:
            return billsNearlyDueCount
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
                Task {
                    await self?.iCloudSync.refresh()
                    await self?.notesService.reloadWaitingForCloudImport()
                    await self?.rescheduleBillReminders()
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
