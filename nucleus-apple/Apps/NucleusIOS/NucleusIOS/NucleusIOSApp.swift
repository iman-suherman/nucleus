import NucleusCore
import NucleusUI
import SwiftData
import SwiftUI
import UserNotifications

@main
struct NucleusIOSApp: App {
    @StateObject private var viewModel = MobileAppViewModel()
    @StateObject private var deviceLock = MobileDeviceLockService.shared

    init() {
        UNUserNotificationCenter.current().delegate = MobileNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(viewModel)
                .environmentObject(deviceLock)
        }
    }
}
