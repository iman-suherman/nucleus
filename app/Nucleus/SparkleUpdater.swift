import AppKit
import Sparkle

/// Sparkle auto-updates — Debug uses local website, Release uses nucleus-registry appcast.
final class SparkleUpdaterController: NSObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdaterController()

    private static let lastForegroundCheckKey = "nucleus.sparkle.lastForegroundUpdateCheck"

    private var controller: SPUStandardUpdaterController!

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        configureUpdater()
        controller.startUpdater()
    }

    var updater: SPUUpdater {
        controller.updater
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func checkForUpdatesInForegroundIfNeeded() {
        guard NSApp.isActive else { return }
        guard Self.isMainWindowVisible else { return }
        guard shouldRunDailyCheck else { return }

        UserDefaults.standard.set(Date(), forKey: Self.lastForegroundCheckKey)
        updater.checkForUpdatesInBackground()
    }

    private static var isMainWindowVisible: Bool {
        NSApp.windows.contains { $0.canBecomeMain && $0.isVisible }
    }

    private var shouldRunDailyCheck: Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: Self.lastForegroundCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) >= dailyCheckInterval
    }

    private var dailyCheckInterval: TimeInterval {
        #if DEBUG
        300
        #else
        86_400
        #endif
    }

    private func configureUpdater() {
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = true
    }
}
