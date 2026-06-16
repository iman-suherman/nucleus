import AppKit
import SwiftUI

@main
struct NucleusMenuBarApp: App {
    @StateObject private var controller = MenuBarDataController()

    var body: some Scene {
        MenuBarExtra("Nucleus", systemImage: "doc.on.clipboard") {
            MenuBarPopoverView(controller: controller)
                .onAppear { controller.reload() }
        }
        .menuBarExtraStyle(.window)
    }
}
