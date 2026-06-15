import AppKit
import Foundation
import NucleusKit
import SwiftUI

@MainActor
final class WindowLayoutController {
    static let shared = WindowLayoutController()

    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private weak var trackedWindow: NSWindow?
    private var onLayoutChange: ((WindowLayoutState) -> Void)?

    private init() {}

    func startTracking(onChange: @escaping (WindowLayoutState) -> Void) {
        onLayoutChange = onChange
    }

    func attach(to window: NSWindow?) {
        guard let window, trackedWindow !== window else { return }
        detachObservers()
        trackedWindow = window
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.publishCurrentLayout()
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.publishCurrentLayout()
        }
    }

    func apply(_ layout: WindowLayoutState?, sidebarWidth: CGFloat? = nil, notesListWidth: CGFloat? = nil) {
        guard let layout else { return }
        guard let window = trackedWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }

        var frame = window.frame
        frame.size = NSSize(width: max(layout.width, 1180), height: max(layout.height, 780))
        if let originX = layout.originX, let originY = layout.originY {
            frame.origin = NSPoint(x: originX, y: originY)
        }
        window.setFrame(frame, display: true)
    }

    func captureCurrentLayout(
        sidebarWidth: CGFloat?,
        notesListWidth: CGFloat?
    ) -> WindowLayoutState? {
        guard let window = trackedWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return nil }
        let frame = window.frame
        return WindowLayoutState(
            width: Double(frame.size.width),
            height: Double(frame.size.height),
            originX: Double(frame.origin.x),
            originY: Double(frame.origin.y),
            sidebarWidth: sidebarWidth.map(Double.init),
            notesListWidth: notesListWidth.map(Double.init)
        )
    }

    private func publishCurrentLayout() {
        guard let layout = captureCurrentLayout(sidebarWidth: nil, notesListWidth: nil) else { return }
        onLayoutChange?(layout)
    }

    private func detachObservers() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
    }
}

struct WindowLayoutAccessor: NSViewRepresentable {
    let onWindowReady: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                onWindowReady(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindowReady(window)
            }
        }
    }
}
