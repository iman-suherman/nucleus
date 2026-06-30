import AppKit
import CalendarKit
import DatabaseKit
import EventKit
import Foundation
import NucleusKit
import SwiftData
import SyncKit

enum CalendarAccessSettingsPane {
    case calendars

    var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendar")
    }
}

@MainActor
final class MacCalendarSyncService: ObservableObject {
    static let shared = MacCalendarSyncService()

    @Published private(set) var accessState: CalendarAccessState = .notDetermined
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncError: String?

    private weak var viewModel: AppViewModel?
    private var refreshTimer: Timer?
    private var reminderRefreshTimer: Timer?
    private var storeChangedObserver: NSObjectProtocol?

    private init() {}

    func start(viewModel: AppViewModel) {
        self.viewModel = viewModel
        refreshAccessState()
        registerForStoreChanges()
        startPeriodicRefresh()
        Task { await syncIfAuthorized() }
    }

    func refreshAccessState() {
        accessState = EventKitCalendarClient.currentAccessState()
    }

    func openCalendarAccessSettings() {
        guard let url = CalendarAccessSettingsPane.calendars.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func requestAccessAndSync() async {
        let result = await EventKitCalendarClient.requestAccess()
        accessState = result.state
        if let errorMessage = result.errorMessage, accessState != .authorized {
            lastSyncError = errorMessage
        }
        await syncIfAuthorized()
    }

    func syncIfAuthorized() async {
        refreshAccessState()
        guard accessState == .authorized else { return }
        guard let viewModel else { return }

        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        let fetched = EventKitCalendarClient.fetchUpcomingEvents(daysAhead: 14)
        let context = ModelContext(viewModel.modelContainer)

        do {
            try CalendarRepository.replaceEvents(fetched, context: context)
            viewModel.calendarEvents = fetched
            if let exported = try? NucleusDatabase.exportCalendarToCloudKit(context: context, force: true),
               exported > 0 {
                CloudKitSyncService.shared.log("Queued \(exported) calendar event(s) for iCloud export")
            }
            await viewModel.refreshMeetingReminders()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func registerForStoreChanges() {
        guard storeChangedObserver == nil else { return }
        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.syncIfAuthorized()
            }
        }
    }

    private func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncIfAuthorized()
            }
        }

        reminderRefreshTimer?.invalidate()
        reminderRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.viewModel?.refreshMeetingReminders()
            }
        }
    }
}
