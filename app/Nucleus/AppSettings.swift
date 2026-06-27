import Combine
import Foundation
import SwiftUI
import AppKit
import UserNotifications
import NucleusKit

enum MailNotificationSound: String, CaseIterable, Identifiable {
    case funky = "Funky"
    case nucleusMail = "NucleusMail"
    case system = "System"
    case silent = "Silent"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .funky: return "Funky"
        case .nucleusMail: return "Nucleus Mail"
        case .system: return "System default"
        case .silent: return "Silent"
        }
    }

    var notificationSound: UNNotificationSound? {
        switch self {
        case .funky, .nucleusMail:
            installInNotificationSupportIfNeeded()
            return UNNotificationSound(named: UNNotificationSoundName(rawValue))
        case .system:
            return .default
        case .silent:
            return nil
        }
    }

    var bundleSoundURL: URL? {
        switch self {
        case .silent, .system:
            return nil
        case .funky, .nucleusMail:
            return Bundle.main.url(forResource: rawValue, withExtension: "caf")
        }
    }

    func playAlert() {
        switch self {
        case .silent:
            return
        case .system:
            NSSound(named: NSSound.Name("Hero"))?.play()
        case .funky, .nucleusMail:
            guard let url = bundleSoundURL else { return }
            NSSound(contentsOf: url, byReference: false)?.play()
        }
    }

    static func prepareNotificationSounds() {
        funky.installInNotificationSupportIfNeeded()
        nucleusMail.installInNotificationSupportIfNeeded()
    }

    private func installInNotificationSupportIfNeeded() {
        guard let source = bundleSoundURL else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nucleus/Library/Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let destination = support.appendingPathComponent("\(rawValue).caf")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? FileManager.default.copyItem(at: source, to: destination)
    }
}

enum ChatNotificationSound: String, CaseIterable, Identifiable {
    case funky = "Funky"
    case nucleusMail = "NucleusMail"
    case system = "System"
    case silent = "Silent"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .funky: return "Funky"
        case .nucleusMail: return "Nucleus Mail"
        case .system: return "System default"
        case .silent: return "Silent"
        }
    }

    var notificationSound: UNNotificationSound? {
        switch self {
        case .funky, .nucleusMail:
            installInNotificationSupportIfNeeded()
            return UNNotificationSound(named: UNNotificationSoundName(rawValue))
        case .system:
            return .default
        case .silent:
            return nil
        }
    }

    var bundleSoundURL: URL? {
        switch self {
        case .silent, .system:
            return nil
        case .funky, .nucleusMail:
            return Bundle.main.url(forResource: rawValue, withExtension: "caf")
        }
    }

    func playAlert() {
        switch self {
        case .silent:
            return
        case .system:
            NSSound(named: NSSound.Name("Hero"))?.play()
        case .funky, .nucleusMail:
            guard let url = bundleSoundURL else { return }
            NSSound(contentsOf: url, byReference: false)?.play()
        }
    }

    static func prepareNotificationSounds() {
        funky.installInNotificationSupportIfNeeded()
        nucleusMail.installInNotificationSupportIfNeeded()
    }

    private func installInNotificationSupportIfNeeded() {
        guard let source = bundleSoundURL else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nucleus/Library/Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let destination = support.appendingPathComponent("\(rawValue).caf")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? FileManager.default.copyItem(at: source, to: destination)
    }
}

enum SidebarSize: String, CaseIterable, Identifiable, Codable {
    case regular
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .regular: return "Regular"
        case .compact: return "Compact"
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .regular: return 260
        case .compact: return 68
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .regular: return 280
        case .compact: return 72
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .regular: return 340
        case .compact: return 80
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let mailSyncInterval = "nucleus.settings.mailSyncInterval"
        static let mailNotificationSound = "nucleus.settings.mailNotificationSound"
        static let mailNotificationSoundByAccount = "nucleus.settings.mailNotificationSoundByAccount"
        static let chatNotificationSound = "nucleus.settings.chatNotificationSound"
        static let chatNotificationSoundByAccount = "nucleus.settings.chatNotificationSoundByAccount"
        static let selectedMailAccountID = "nucleus.settings.selectedMailAccountID"
        static let selectedCalendarAccountID = "nucleus.settings.selectedCalendarAccountID"
        static let selectedChatAccountID = "nucleus.settings.selectedChatAccountID"
        static let emailNotificationsEnabled = "nucleus.settings.emailNotificationsEnabled"
        static let chatNotificationsEnabled = "nucleus.settings.chatNotificationsEnabled"
        static let calendarNotificationsEnabled = "nucleus.settings.calendarNotificationsEnabled"
        static let clipboardSyncEnabled = "nucleus.settings.clipboardSyncEnabled"
        static let clipboardSaveToNotesEnabled = "nucleus.settings.clipboardSaveToNotesEnabled"
        static let clipboardPasswordDetectionEnabled = "nucleus.settings.clipboardPasswordDetectionEnabled"
        static let menuBarEnabled = "nucleus.settings.menuBarEnabled"
        static let iCloudKeychainTokenSyncEnabled = "nucleus.settings.iCloudKeychainTokenSyncEnabled"
        static let selectedWorkspacePane = "nucleus.settings.selectedWorkspacePane"
        static let windowLayout = "nucleus.settings.windowLayout"
        static let hourlyBeepEnabled = "nucleus.settings.hourlyBeepEnabled"
        static let hourlyBeepSound = "nucleus.settings.hourlyBeepSound"
        static let expectedMonthlyIncome = "nucleus.settings.expectedMonthlyIncome"
        static let billNotificationsEnabled = "nucleus.settings.billNotificationsEnabled"
        static let billNotificationHour = "nucleus.settings.billNotificationHour"
        static let billNotifySevenDaysBefore = "nucleus.settings.billNotifySevenDaysBefore"
        static let billNotifyThreeDaysBefore = "nucleus.settings.billNotifyThreeDaysBefore"
        static let billNotifyOneDayBefore = "nucleus.settings.billNotifyOneDayBefore"
        static let billNotifyOnDueDate = "nucleus.settings.billNotifyOnDueDate"
        static let dashboardPreferences = "nucleus.settings.dashboardPreferences"
        static let sidebarSize = "nucleus.settings.sidebarSize"
        static let workspacePaneOrder = "nucleus.settings.workspacePaneOrder"
        static let tmuxSessionOrder = "nucleus.settings.tmuxSessionOrder"
        static let publicHolidayCountryCodes = "nucleus.settings.publicHolidayCountryCodes"
        static let mediaFavoritePlaylists = "nucleus.settings.mediaFavoritePlaylists"
        static let mediaShortcuts = "nucleus.settings.mediaShortcuts"
    }

    static let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    static let marketingWebsiteURL = URL(string: "https://nucleus.suherman.net")!

    static func openMarketingWebsite() {
        NSWorkspace.shared.open(marketingWebsiteURL)
    }

    @Published var mailSyncInterval: TimeInterval {
        didSet { UserDefaults.standard.set(mailSyncInterval, forKey: Keys.mailSyncInterval) }
    }

    @Published var mailNotificationSound: MailNotificationSound {
        didSet { UserDefaults.standard.set(mailNotificationSound.rawValue, forKey: Keys.mailNotificationSound) }
    }

    @Published private(set) var mailNotificationSoundOverrides: [UUID: MailNotificationSound] = [:] {
        didSet { persistMailNotificationSoundOverrides() }
    }

    @Published var chatNotificationSound: ChatNotificationSound {
        didSet { UserDefaults.standard.set(chatNotificationSound.rawValue, forKey: Keys.chatNotificationSound) }
    }

    @Published private(set) var chatNotificationSoundOverrides: [UUID: ChatNotificationSound] = [:] {
        didSet { persistChatNotificationSoundOverrides() }
    }

    @Published var selectedMailAccountID: UUID? {
        didSet {
            if let selectedMailAccountID {
                UserDefaults.standard.set(selectedMailAccountID.uuidString, forKey: Keys.selectedMailAccountID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedMailAccountID)
            }
        }
    }

    @Published var selectedCalendarAccountID: UUID? {
        didSet {
            if let selectedCalendarAccountID {
                UserDefaults.standard.set(selectedCalendarAccountID.uuidString, forKey: Keys.selectedCalendarAccountID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedCalendarAccountID)
            }
        }
    }

    @Published var selectedChatAccountID: UUID? {
        didSet {
            if let selectedChatAccountID {
                UserDefaults.standard.set(selectedChatAccountID.uuidString, forKey: Keys.selectedChatAccountID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedChatAccountID)
            }
        }
    }

    @Published var emailNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(emailNotificationsEnabled, forKey: Keys.emailNotificationsEnabled) }
    }

    @Published var chatNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(chatNotificationsEnabled, forKey: Keys.chatNotificationsEnabled) }
    }

    @Published var calendarNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarNotificationsEnabled, forKey: Keys.calendarNotificationsEnabled) }
    }

    @Published var clipboardSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardSyncEnabled, forKey: Keys.clipboardSyncEnabled) }
    }

    @Published var clipboardSaveToNotesEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardSaveToNotesEnabled, forKey: Keys.clipboardSaveToNotesEnabled) }
    }

    @Published var clipboardPasswordDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardPasswordDetectionEnabled, forKey: Keys.clipboardPasswordDetectionEnabled) }
    }

    @Published var menuBarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(menuBarEnabled, forKey: Keys.menuBarEnabled)
        }
    }

    @Published var iCloudKeychainTokenSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(iCloudKeychainTokenSyncEnabled, forKey: Keys.iCloudKeychainTokenSyncEnabled) }
    }

    @Published var selectedWorkspacePane: String? {
        didSet {
            if let selectedWorkspacePane {
                UserDefaults.standard.set(selectedWorkspacePane, forKey: Keys.selectedWorkspacePane)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedWorkspacePane)
            }
        }
    }

    @Published var windowLayout: WindowLayoutState? {
        didSet {
            if let windowLayout, let data = try? JSONEncoder().encode(windowLayout) {
                UserDefaults.standard.set(data, forKey: Keys.windowLayout)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.windowLayout)
            }
        }
    }

    @Published var hourlyBeepEnabled: Bool {
        didSet { UserDefaults.standard.set(hourlyBeepEnabled, forKey: Keys.hourlyBeepEnabled) }
    }

    @Published var hourlyBeepSound: HourlyBeepSound {
        didSet { UserDefaults.standard.set(hourlyBeepSound.rawValue, forKey: Keys.hourlyBeepSound) }
    }

    @Published var expectedMonthlyIncome: Double {
        didSet { UserDefaults.standard.set(expectedMonthlyIncome, forKey: Keys.expectedMonthlyIncome) }
    }

    @Published var billNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(billNotificationsEnabled, forKey: Keys.billNotificationsEnabled) }
    }

    @Published var billNotificationHour: Int {
        didSet { UserDefaults.standard.set(billNotificationHour, forKey: Keys.billNotificationHour) }
    }

    @Published var billNotifySevenDaysBefore: Bool {
        didSet { UserDefaults.standard.set(billNotifySevenDaysBefore, forKey: Keys.billNotifySevenDaysBefore) }
    }

    @Published var billNotifyThreeDaysBefore: Bool {
        didSet { UserDefaults.standard.set(billNotifyThreeDaysBefore, forKey: Keys.billNotifyThreeDaysBefore) }
    }

    @Published var billNotifyOneDayBefore: Bool {
        didSet { UserDefaults.standard.set(billNotifyOneDayBefore, forKey: Keys.billNotifyOneDayBefore) }
    }

    @Published var billNotifyOnDueDate: Bool {
        didSet { UserDefaults.standard.set(billNotifyOnDueDate, forKey: Keys.billNotifyOnDueDate) }
    }

    @Published var dashboardPreferences: DashboardPreferences {
        didSet { Self.persistDashboardPreferences(dashboardPreferences) }
    }

    @Published var sidebarSize: SidebarSize {
        didSet { UserDefaults.standard.set(sidebarSize.rawValue, forKey: Keys.sidebarSize) }
    }

    @Published var workspacePaneOrder: [WorkspacePane] {
        didSet {
            UserDefaults.standard.set(
                workspacePaneOrder.map(\.rawValue),
                forKey: Keys.workspacePaneOrder
            )
        }
    }

    @Published var tmuxSessionOrder: [String] {
        didSet {
            UserDefaults.standard.set(tmuxSessionOrder, forKey: Keys.tmuxSessionOrder)
        }
    }

    @Published var publicHolidayCountryCodes: [String] {
        didSet {
            let normalized = DashboardPublicHolidayService.normalizedCountryCodes(publicHolidayCountryCodes)
            if normalized != publicHolidayCountryCodes {
                publicHolidayCountryCodes = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Keys.publicHolidayCountryCodes)
        }
    }

    @Published var mediaFavoritePlaylists: [MediaFavoritePlaylist] {
        didSet { Self.persistMediaFavoritePlaylists(mediaFavoritePlaylists) }
    }

    @Published var mediaShortcuts: [MediaShortcut] {
        didSet { Self.persistMediaShortcuts(mediaShortcuts) }
    }

    func addMediaFavoritePlaylist(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mediaFavoritePlaylists.append(MediaFavoritePlaylist(name: trimmed))
    }

    func removeMediaFavoritePlaylist(id: UUID) {
        mediaFavoritePlaylists.removeAll { $0.id == id }
    }

    func addMediaShortcut(_ shortcut: MediaShortcut) {
        let trimmed = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mediaShortcuts.append(
            MediaShortcut(id: shortcut.id, name: trimmed, detail: shortcut.detail.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    func removeMediaShortcut(id: UUID) {
        mediaShortcuts.removeAll { $0.id == id }
    }

    var billDueReminderConfiguration: BillDueReminderConfiguration {
        BillDueReminderConfiguration(
            enabled: billNotificationsEnabled,
            hour: billNotificationHour,
            notifySevenDaysBefore: billNotifySevenDaysBefore,
            notifyThreeDaysBefore: billNotifyThreeDaysBefore,
            notifyOneDayBefore: billNotifyOneDayBefore,
            notifyOnDueDate: billNotifyOnDueDate
        )
    }

    var sidebarWidth: CGFloat {
        CGFloat(windowLayout?.sidebarWidth ?? Double(SidebarSize.regular.idealWidth))
    }

    var sidebarColumnMinWidth: CGFloat {
        sidebarSize.minWidth
    }

    var sidebarColumnIdealWidth: CGFloat {
        switch sidebarSize {
        case .regular:
            return sidebarWidth
        case .compact:
            return sidebarSize.idealWidth
        }
    }

    var sidebarColumnMaxWidth: CGFloat {
        sidebarSize.maxWidth
    }

    var notesListWidth: CGFloat {
        CGFloat(windowLayout?.notesListWidth ?? 280)
    }

    func mailNotificationSound(for accountID: UUID) -> MailNotificationSound {
        mailNotificationSoundOverrides[accountID] ?? mailNotificationSound
    }

    func setMailNotificationSound(_ sound: MailNotificationSound, for accountID: UUID) {
        mailNotificationSoundOverrides[accountID] = sound
    }

    func clearMailNotificationSound(for accountID: UUID) {
        mailNotificationSoundOverrides.removeValue(forKey: accountID)
    }

    func replaceMailNotificationSoundOverrides(_ overrides: [UUID: MailNotificationSound]) {
        mailNotificationSoundOverrides = overrides
    }

    func chatNotificationSound(for accountID: UUID) -> ChatNotificationSound {
        chatNotificationSoundOverrides[accountID] ?? chatNotificationSound
    }

    func setChatNotificationSound(_ sound: ChatNotificationSound, for accountID: UUID) {
        chatNotificationSoundOverrides[accountID] = sound
    }

    func clearChatNotificationSound(for accountID: UUID) {
        chatNotificationSoundOverrides.removeValue(forKey: accountID)
    }

    func replaceChatNotificationSoundOverrides(_ overrides: [UUID: ChatNotificationSound]) {
        chatNotificationSoundOverrides = overrides
    }

    private init() {
        mailSyncInterval = UserDefaults.standard.object(forKey: Keys.mailSyncInterval) as? TimeInterval ?? 60
        if let raw = UserDefaults.standard.string(forKey: Keys.mailNotificationSound),
           let sound = MailNotificationSound(rawValue: raw) {
            mailNotificationSound = sound
        } else {
            mailNotificationSound = .nucleusMail
        }
        mailNotificationSoundOverrides = Self.loadMailNotificationSoundOverrides()

        if let raw = UserDefaults.standard.string(forKey: Keys.chatNotificationSound),
           let sound = ChatNotificationSound(rawValue: raw) {
            chatNotificationSound = sound
        } else {
            chatNotificationSound = .funky
        }
        chatNotificationSoundOverrides = Self.loadChatNotificationSoundOverrides()

        if let raw = UserDefaults.standard.string(forKey: Keys.selectedMailAccountID),
           let id = UUID(uuidString: raw) {
            selectedMailAccountID = id
        } else {
            selectedMailAccountID = nil
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.selectedCalendarAccountID),
           let id = UUID(uuidString: raw) {
            selectedCalendarAccountID = id
        } else {
            selectedCalendarAccountID = nil
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.selectedChatAccountID),
           let id = UUID(uuidString: raw) {
            selectedChatAccountID = id
        } else {
            selectedChatAccountID = nil
        }

        if UserDefaults.standard.object(forKey: Keys.emailNotificationsEnabled) != nil {
            emailNotificationsEnabled = UserDefaults.standard.bool(forKey: Keys.emailNotificationsEnabled)
        } else {
            emailNotificationsEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.chatNotificationsEnabled) != nil {
            chatNotificationsEnabled = UserDefaults.standard.bool(forKey: Keys.chatNotificationsEnabled)
        } else {
            chatNotificationsEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.calendarNotificationsEnabled) != nil {
            calendarNotificationsEnabled = UserDefaults.standard.bool(forKey: Keys.calendarNotificationsEnabled)
        } else {
            calendarNotificationsEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.clipboardSyncEnabled) != nil {
            clipboardSyncEnabled = UserDefaults.standard.bool(forKey: Keys.clipboardSyncEnabled)
        } else {
            clipboardSyncEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.clipboardSaveToNotesEnabled) != nil {
            clipboardSaveToNotesEnabled = UserDefaults.standard.bool(forKey: Keys.clipboardSaveToNotesEnabled)
        } else {
            clipboardSaveToNotesEnabled = false
        }

        if UserDefaults.standard.object(forKey: Keys.clipboardPasswordDetectionEnabled) != nil {
            clipboardPasswordDetectionEnabled = UserDefaults.standard.bool(forKey: Keys.clipboardPasswordDetectionEnabled)
        } else {
            clipboardPasswordDetectionEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.menuBarEnabled) != nil {
            menuBarEnabled = UserDefaults.standard.bool(forKey: Keys.menuBarEnabled)
        } else {
            menuBarEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.iCloudKeychainTokenSyncEnabled) != nil {
            iCloudKeychainTokenSyncEnabled = UserDefaults.standard.bool(forKey: Keys.iCloudKeychainTokenSyncEnabled)
        } else {
            iCloudKeychainTokenSyncEnabled = true
        }

        selectedWorkspacePane = UserDefaults.standard.string(forKey: Keys.selectedWorkspacePane)

        if let data = UserDefaults.standard.data(forKey: Keys.windowLayout),
           let layout = try? JSONDecoder().decode(WindowLayoutState.self, from: data) {
            windowLayout = layout
        } else {
            windowLayout = nil
        }

        if UserDefaults.standard.object(forKey: Keys.hourlyBeepEnabled) != nil {
            hourlyBeepEnabled = UserDefaults.standard.bool(forKey: Keys.hourlyBeepEnabled)
        } else {
            hourlyBeepEnabled = false
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.hourlyBeepSound),
           let sound = HourlyBeepSound(rawValue: raw) {
            hourlyBeepSound = sound
        } else {
            hourlyBeepSound = .classic
        }

        expectedMonthlyIncome = UserDefaults.standard.object(forKey: Keys.expectedMonthlyIncome) as? Double ?? 0

        if UserDefaults.standard.object(forKey: Keys.billNotificationsEnabled) != nil {
            billNotificationsEnabled = UserDefaults.standard.bool(forKey: Keys.billNotificationsEnabled)
        } else {
            billNotificationsEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.billNotificationHour) != nil {
            billNotificationHour = UserDefaults.standard.integer(forKey: Keys.billNotificationHour)
        } else {
            billNotificationHour = 7
        }

        if UserDefaults.standard.object(forKey: Keys.billNotifySevenDaysBefore) != nil {
            billNotifySevenDaysBefore = UserDefaults.standard.bool(forKey: Keys.billNotifySevenDaysBefore)
        } else {
            billNotifySevenDaysBefore = true
        }

        if UserDefaults.standard.object(forKey: Keys.billNotifyThreeDaysBefore) != nil {
            billNotifyThreeDaysBefore = UserDefaults.standard.bool(forKey: Keys.billNotifyThreeDaysBefore)
        } else {
            billNotifyThreeDaysBefore = true
        }

        if UserDefaults.standard.object(forKey: Keys.billNotifyOneDayBefore) != nil {
            billNotifyOneDayBefore = UserDefaults.standard.bool(forKey: Keys.billNotifyOneDayBefore)
        } else {
            billNotifyOneDayBefore = true
        }

        if UserDefaults.standard.object(forKey: Keys.billNotifyOnDueDate) != nil {
            billNotifyOnDueDate = UserDefaults.standard.bool(forKey: Keys.billNotifyOnDueDate)
        } else {
            billNotifyOnDueDate = true
        }

        dashboardPreferences = Self.loadDashboardPreferences()

        if let raw = UserDefaults.standard.string(forKey: Keys.sidebarSize),
           let size = SidebarSize(rawValue: raw) {
            sidebarSize = size
        } else {
            sidebarSize = .regular
        }
        workspacePaneOrder = Self.resolvedWorkspacePaneOrder(
            stored: UserDefaults.standard.stringArray(forKey: Keys.workspacePaneOrder)
        )
        tmuxSessionOrder = UserDefaults.standard.stringArray(forKey: Keys.tmuxSessionOrder) ?? []
        publicHolidayCountryCodes = UserDefaults.standard.stringArray(forKey: Keys.publicHolidayCountryCodes) ?? []
        mediaFavoritePlaylists = Self.loadMediaFavoritePlaylists()
        mediaShortcuts = Self.loadMediaShortcuts()
    }

    func resetDashboardPreferences() {
        dashboardPreferences = DashboardPreferences()
        publicHolidayCountryCodes = []
    }

    static func resolvedWorkspacePaneOrder(stored: [String]?) -> [WorkspacePane] {
        let validPanes = Set(WorkspacePane.reorderableWorkspaces)
        guard let stored, !stored.isEmpty else {
            return WorkspacePane.reorderableWorkspaces
        }

        var ordered = stored
            .compactMap { WorkspacePane(rawValue: $0) }
            .filter { $0.isReorderableSidebarItem && validPanes.contains($0) }
        for pane in WorkspacePane.reorderableWorkspaces where !ordered.contains(pane) {
            ordered.append(pane)
        }
        return ordered
    }

    private static func persistDashboardPreferences(_ preferences: DashboardPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Keys.dashboardPreferences)
    }

    private static func loadDashboardPreferences() -> DashboardPreferences {
        if let data = UserDefaults.standard.data(forKey: Keys.dashboardPreferences),
           let preferences = try? JSONDecoder().decode(DashboardPreferences.self, from: data) {
            return preferences
        }

        var preferences = DashboardPreferences()
        if UserDefaults.standard.object(forKey: "nucleus.dashboard.intelligentInsightExpanded") != nil {
            preferences.intelligentInsightExpanded = UserDefaults.standard.bool(
                forKey: "nucleus.dashboard.intelligentInsightExpanded"
            )
        }
        if UserDefaults.standard.object(forKey: "nucleus.dashboard.clipboardDayExpanded") != nil {
            preferences.clipboardDayExpanded = UserDefaults.standard.bool(
                forKey: "nucleus.dashboard.clipboardDayExpanded"
            )
        }
        return preferences
    }

    private func persistMailNotificationSoundOverrides() {
        let encoded = Dictionary(
            uniqueKeysWithValues: mailNotificationSoundOverrides.map { ($0.key.uuidString, $0.value.rawValue) }
        )
        UserDefaults.standard.set(encoded, forKey: Keys.mailNotificationSoundByAccount)
    }

    private static func loadMailNotificationSoundOverrides() -> [UUID: MailNotificationSound] {
        guard let raw = UserDefaults.standard.dictionary(forKey: Keys.mailNotificationSoundByAccount) as? [String: String] else {
            return [:]
        }

        var overrides: [UUID: MailNotificationSound] = [:]
        for (accountIDRaw, soundRaw) in raw {
            guard let accountID = UUID(uuidString: accountIDRaw),
                  let sound = MailNotificationSound(rawValue: soundRaw) else { continue }
            overrides[accountID] = sound
        }
        return overrides
    }

    private func persistChatNotificationSoundOverrides() {
        let encoded = Dictionary(
            uniqueKeysWithValues: chatNotificationSoundOverrides.map { ($0.key.uuidString, $0.value.rawValue) }
        )
        UserDefaults.standard.set(encoded, forKey: Keys.chatNotificationSoundByAccount)
    }

    private static func loadChatNotificationSoundOverrides() -> [UUID: ChatNotificationSound] {
        guard let raw = UserDefaults.standard.dictionary(forKey: Keys.chatNotificationSoundByAccount) as? [String: String] else {
            return [:]
        }

        var overrides: [UUID: ChatNotificationSound] = [:]
        for (accountIDRaw, soundRaw) in raw {
            guard let accountID = UUID(uuidString: accountIDRaw),
                  let sound = ChatNotificationSound(rawValue: soundRaw) else { continue }
            overrides[accountID] = sound
        }
        return overrides
    }

    private static func persistMediaFavoritePlaylists(_ playlists: [MediaFavoritePlaylist]) {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: Keys.mediaFavoritePlaylists)
    }

    private static func loadMediaFavoritePlaylists() -> [MediaFavoritePlaylist] {
        guard let data = UserDefaults.standard.data(forKey: Keys.mediaFavoritePlaylists),
              let playlists = try? JSONDecoder().decode([MediaFavoritePlaylist].self, from: data) else {
            return []
        }
        return playlists
    }

    private static func persistMediaShortcuts(_ shortcuts: [MediaShortcut]) {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: Keys.mediaShortcuts)
    }

    private static func loadMediaShortcuts() -> [MediaShortcut] {
        guard let data = UserDefaults.standard.data(forKey: Keys.mediaShortcuts),
              let shortcuts = try? JSONDecoder().decode([MediaShortcut].self, from: data) else {
            return []
        }
        return shortcuts
    }
}

struct DashboardPreferences: Codable, Equatable {
    var quoteEnabled: Bool
    var intelligentInsightEnabled: Bool
    var clipboardDayEnabled: Bool
    var summaryMetricsEnabled: Bool
    var billPreparationEnabled: Bool
    var weatherEnabled: Bool
    var resourceUsageEnabled: Bool
    var cloudSyncPanelEnabled: Bool
    var publicHolidayEnabled: Bool
    var publicHolidayExpanded: Bool
    var newsFeedEnabled: Bool
    var productivityChartEnabled: Bool
    var intelligentInsightExpanded: Bool
    var clipboardDayExpanded: Bool
    var contextPanelsExpanded: Bool
    var newsFeedExpanded: Bool
    var summaryExpanded: Bool
    var paymentPreparationExpanded: Bool
    var productivityExpanded: Bool
    var nucleusAIEnabled: Bool
    var appleMusicEnabled: Bool
    var nucleusAIExpanded: Bool
    var appleMusicExpanded: Bool

    init(
        quoteEnabled: Bool = true,
        intelligentInsightEnabled: Bool = true,
        clipboardDayEnabled: Bool = true,
        summaryMetricsEnabled: Bool = true,
        billPreparationEnabled: Bool = true,
        weatherEnabled: Bool = true,
        resourceUsageEnabled: Bool = true,
        cloudSyncPanelEnabled: Bool = true,
        publicHolidayEnabled: Bool = true,
        publicHolidayExpanded: Bool = true,
        newsFeedEnabled: Bool = true,
        productivityChartEnabled: Bool = true,
        intelligentInsightExpanded: Bool = true,
        clipboardDayExpanded: Bool = true,
        contextPanelsExpanded: Bool = true,
        newsFeedExpanded: Bool = true,
        summaryExpanded: Bool = true,
        paymentPreparationExpanded: Bool = true,
        productivityExpanded: Bool = true,
        nucleusAIEnabled: Bool = true,
        appleMusicEnabled: Bool = true,
        nucleusAIExpanded: Bool = true,
        appleMusicExpanded: Bool = true
    ) {
        self.quoteEnabled = quoteEnabled
        self.intelligentInsightEnabled = intelligentInsightEnabled
        self.clipboardDayEnabled = clipboardDayEnabled
        self.summaryMetricsEnabled = summaryMetricsEnabled
        self.billPreparationEnabled = billPreparationEnabled
        self.weatherEnabled = weatherEnabled
        self.resourceUsageEnabled = resourceUsageEnabled
        self.cloudSyncPanelEnabled = cloudSyncPanelEnabled
        self.publicHolidayEnabled = publicHolidayEnabled
        self.publicHolidayExpanded = publicHolidayExpanded
        self.newsFeedEnabled = newsFeedEnabled
        self.productivityChartEnabled = productivityChartEnabled
        self.intelligentInsightExpanded = intelligentInsightExpanded
        self.clipboardDayExpanded = clipboardDayExpanded
        self.contextPanelsExpanded = contextPanelsExpanded
        self.newsFeedExpanded = newsFeedExpanded
        self.summaryExpanded = summaryExpanded
        self.paymentPreparationExpanded = paymentPreparationExpanded
        self.productivityExpanded = productivityExpanded
        self.nucleusAIEnabled = nucleusAIEnabled
        self.appleMusicEnabled = appleMusicEnabled
        self.nucleusAIExpanded = nucleusAIExpanded
        self.appleMusicExpanded = appleMusicExpanded
    }

    private enum CodingKeys: String, CodingKey {
        case quoteEnabled, intelligentInsightEnabled, clipboardDayEnabled
        case summaryMetricsEnabled, billPreparationEnabled, weatherEnabled
        case resourceUsageEnabled, cloudSyncPanelEnabled, publicHolidayEnabled, publicHolidayExpanded
        case newsFeedEnabled, productivityChartEnabled
        case intelligentInsightExpanded, clipboardDayExpanded
        case contextPanelsExpanded, newsFeedExpanded, summaryExpanded
        case paymentPreparationExpanded, productivityExpanded
        case nucleusAIEnabled, appleMusicEnabled, nucleusAIExpanded, appleMusicExpanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quoteEnabled = try container.decodeIfPresent(Bool.self, forKey: .quoteEnabled) ?? true
        intelligentInsightEnabled = try container.decodeIfPresent(Bool.self, forKey: .intelligentInsightEnabled) ?? true
        clipboardDayEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardDayEnabled) ?? true
        summaryMetricsEnabled = try container.decodeIfPresent(Bool.self, forKey: .summaryMetricsEnabled) ?? true
        billPreparationEnabled = try container.decodeIfPresent(Bool.self, forKey: .billPreparationEnabled) ?? true
        weatherEnabled = try container.decodeIfPresent(Bool.self, forKey: .weatherEnabled) ?? true
        resourceUsageEnabled = try container.decodeIfPresent(Bool.self, forKey: .resourceUsageEnabled) ?? true
        cloudSyncPanelEnabled = try container.decodeIfPresent(Bool.self, forKey: .cloudSyncPanelEnabled) ?? true
        publicHolidayEnabled = try container.decodeIfPresent(Bool.self, forKey: .publicHolidayEnabled) ?? true
        publicHolidayExpanded = try container.decodeIfPresent(Bool.self, forKey: .publicHolidayExpanded) ?? true
        newsFeedEnabled = try container.decodeIfPresent(Bool.self, forKey: .newsFeedEnabled) ?? true
        productivityChartEnabled = try container.decodeIfPresent(Bool.self, forKey: .productivityChartEnabled) ?? true
        intelligentInsightExpanded = try container.decodeIfPresent(Bool.self, forKey: .intelligentInsightExpanded) ?? true
        clipboardDayExpanded = try container.decodeIfPresent(Bool.self, forKey: .clipboardDayExpanded) ?? true
        contextPanelsExpanded = try container.decodeIfPresent(Bool.self, forKey: .contextPanelsExpanded) ?? true
        newsFeedExpanded = try container.decodeIfPresent(Bool.self, forKey: .newsFeedExpanded) ?? true
        summaryExpanded = try container.decodeIfPresent(Bool.self, forKey: .summaryExpanded) ?? true
        paymentPreparationExpanded = try container.decodeIfPresent(Bool.self, forKey: .paymentPreparationExpanded) ?? true
        productivityExpanded = try container.decodeIfPresent(Bool.self, forKey: .productivityExpanded) ?? true
        nucleusAIEnabled = try container.decodeIfPresent(Bool.self, forKey: .nucleusAIEnabled) ?? true
        appleMusicEnabled = try container.decodeIfPresent(Bool.self, forKey: .appleMusicEnabled) ?? true
        nucleusAIExpanded = try container.decodeIfPresent(Bool.self, forKey: .nucleusAIExpanded) ?? true
        appleMusicExpanded = try container.decodeIfPresent(Bool.self, forKey: .appleMusicExpanded) ?? true
    }
}
