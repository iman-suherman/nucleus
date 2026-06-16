import NucleusCore
import NucleusUI
import SwiftData
import SwiftUI
import UserNotifications

@main
struct NucleusIOSApp: App {
    @StateObject private var viewModel = MobileAppViewModel()

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(viewModel)
                .task {
                    await viewModel.bootstrap()
                }
        }
    }
}
