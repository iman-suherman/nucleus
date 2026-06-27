import AppKit
import SwiftUI

@MainActor
final class MenuBarStatusItemController: NSObject {
    static let shared = MenuBarStatusItemController()

    private var statusItem: NSStatusItem?
    private let popoverSession = MenuBarPopoverSession()
    private weak var controller: MenuBarController?

    private override init() {
        super.init()
    }

    func syncVisibility(enabled: Bool, controller: MenuBarController) {
        self.controller = controller
        if enabled {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }

        let icon = MenuBarNucleusIcon.templateImage()
        icon.isTemplate = true
        button.image = icon
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusItem = item
    }

    private func removeStatusItem() {
        popoverSession.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if shouldShowContextMenu(for: sender) {
            showContextMenu(for: sender)
            return
        }
        togglePopover(anchoredTo: sender)
    }

    private func shouldShowContextMenu(for button: NSStatusBarButton) -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        if event.type == .rightMouseUp {
            return true
        }
        if event.type == .leftMouseUp, event.modifierFlags.contains(.control) {
            return true
        }
        return false
    }

    private func showContextMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()
        let pasteItem = NSMenuItem(
            title: "Paste from Clipboard History",
            action: #selector(pasteFromClipboardHistory),
            keyEquivalent: "V"
        )
        pasteItem.keyEquivalentModifierMask = [.command, .shift]
        pasteItem.target = self
        menu.addItem(pasteItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func pasteFromClipboardHistory() {
        ClipboardPasteController.shared.presentPicker()
    }

    private func togglePopover(anchoredTo anchorView: NSView) {
        guard let controller else { return }

        popoverSession.toggle(
            anchoredTo: anchorView,
            contentSize: NSSize(width: 680, height: 420),
            shouldDismissOnOutsideClick: { [weak controller] in
                controller?.pendingSuggestion == nil
            }
        ) {
            MenuBarPopoverView(controller: controller)
        } onShow: {
            controller.reload()
        }
    }

    func showPasswordSavePopover(entryID: UUID) {
        guard AppSettings.shared.menuBarEnabled else { return }
        guard let controller else { return }
        NucleusNotificationService.shared.clearPasswordNotification(entryID: entryID)
        guard controller.presentPasswordSuggestion(entryID: entryID) else { return }

        if statusItem == nil {
            MenuBarCoordinator.sync(settings: AppSettings.shared, controller: controller)
        }
        guard let anchorView = statusItem?.button else { return }
        presentPasswordPopover(anchoredTo: anchorView, controller: controller)
    }

    private func presentPasswordPopover(anchoredTo anchorView: NSView, controller: MenuBarController) {
        let mainWindows = NSApp.windows.filter { $0.canBecomeMain && $0.isVisible }
        NSApp.activate(ignoringOtherApps: true)

        popoverSession.present(
            anchoredTo: anchorView,
            contentSize: NSSize(width: 680, height: 420),
            shouldDismissOnOutsideClick: { [weak controller] in
                controller?.pendingSuggestion == nil
            }
        ) {
            MenuBarPopoverView(controller: controller)
        } onShow: {
            controller.reload()
            for window in mainWindows where window.isVisible {
                window.orderBack(nil)
            }
        }
    }
}

@MainActor
enum MenuBarCoordinator {
    static func sync(settings: AppSettings, controller: MenuBarController) {
        MenuBarStatusItemController.shared.syncVisibility(
            enabled: settings.menuBarEnabled,
            controller: controller
        )
    }
}
