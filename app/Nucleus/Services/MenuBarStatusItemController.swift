import AppKit
import SwiftUI

private struct MenuBarStatusIconView: View {
    var body: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 22, height: 18)
    }
}

final class MenuBarClickableStatusView: NSView {
    var onClick: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

@MainActor
final class MenuBarStatusItemController: NSObject {
    static let shared = MenuBarStatusItemController()

    private var statusItem: NSStatusItem?
    private var containerView: MenuBarClickableStatusView?
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

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let hostingView = NSHostingView(rootView: MenuBarStatusIconView())
        hostingView.frame.size = NSSize(width: 22, height: 18)

        let container = MenuBarClickableStatusView(frame: hostingView.frame)
        container.onClick = { [weak self, weak container] in
            guard let container else { return }
            self?.togglePopover(anchoredTo: container)
        }
        hostingView.frame.origin = .zero
        container.addSubview(hostingView)

        item.view = container
        statusItem = item
        containerView = container
    }

    private func removeStatusItem() {
        popoverSession.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        containerView = nil
    }

    private func togglePopover(anchoredTo anchorView: NSView) {
        guard let controller else { return }

        popoverSession.toggle(
            anchoredTo: anchorView,
            contentSize: NSSize(width: 680, height: 420)
        ) {
            MenuBarPopoverView(controller: controller)
        } onShow: {
            controller.reload()
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
