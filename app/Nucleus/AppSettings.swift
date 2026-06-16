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
    }

    static let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

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
        CGFloat(windowLayout?.sidebarWidth ?? 280)
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
}
