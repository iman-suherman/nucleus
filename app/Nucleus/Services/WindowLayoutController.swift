import AppKit
import Foundation
import NucleusKit
import SwiftUI

@MainActor
final class WindowLayoutController: NSObject, NSWindowDelegate {
    static let shared = WindowLayoutController()

    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private weak var trackedWindow: NSWindow?
    private var onLayoutChange: ((WindowLayoutState) -> Void)?
    private var hasRestoredInitialFrame = false
    private var isApplyingProgrammatically = false

    private override init() {
        super.init()
    }

    func startTracking(onChange: @escaping (WindowLayoutState) -> Void) {
        onLayoutChange = onChange
    }

    func attach(to window: NSWindow?) {
        guard let window, trackedWindow !== window else { return }
        detachObservers()
        trackedWindow = window
        window.delegate = self
        configureWindowChrome(window)
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
        restoreSavedFrameOnce(from: AppSettings.shared.windowLayout)
    }

    func reapplyWindowChrome() {
        guard let window = trackedWindow else { return }
        configureWindowChrome(window)
    }

    /// Restores saved frame once at launch. Frame is never re-applied after user interaction.
    func restoreSavedFrameOnce(from layout: WindowLayoutState?) {
        guard !hasRestoredInitialFrame else { return }
        guard let window = trackedWindow else { return }
        hasRestoredInitialFrame = true

        var target = window.frame
        if let layout {
            if layout.width > 0, layout.height > 0 {
                target.size = NSSize(
                    width: max(layout.width, 1180),
                    height: max(layout.height, 780)
                )
            }
            if let originX = layout.originX, let originY = layout.originY {
                target.origin = NSPoint(x: originX, y: originY)
            }
        }

        let constrained = frameConstrainedToVisibleScreen(target, on: window, centerIfNeeded: layout == nil)
        guard !framesApproximatelyEqual(window.frame, constrained) else { return }

        isApplyingProgrammatically = true
        window.setFrame(constrained, display: true)
        isApplyingProgrammatically = false
        configureWindowChrome(window)
    }

    private func configureWindowChrome(_ window: NSWindow) {
        window.title = "Nucleus"
        window.titleVisibility = .hidden
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.toolbarStyle = .unified
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === trackedWindow else { return }
        configureWindowChrome(window)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === trackedWindow else { return }
        configureWindowChrome(window)
    }

    private func frameConstrainedToVisibleScreen(
        _ frame: NSRect,
        on window: NSWindow,
        centerIfNeeded: Bool
    ) -> NSRect {
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return frame }

        var result = frame
        result.size.width = min(max(result.size.width, 1180), visible.width)
        result.size.height = min(max(result.size.height, 780), visible.height)

        let intersectsVisible = visible.intersection(result)
        let isMostlyVisible = intersectsVisible.width > result.width * 0.5
            && intersectsVisible.height > result.height * 0.5

        if centerIfNeeded || !isMostlyVisible {
            result.origin = NSPoint(
                x: visible.midX - result.width / 2,
                y: visible.midY - result.height / 2
            )
        }

        if result.minX < visible.minX {
            result.origin.x = visible.minX
        }
        if result.maxX > visible.maxX {
            result.origin.x = visible.maxX - result.width
        }
        if result.minY < visible.minY {
            result.origin.y = visible.minY
        }
        if result.maxY > visible.maxY {
            result.origin.y = visible.maxY - result.height
        }

        return result
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
        guard !isApplyingProgrammatically else { return }
        guard let layout = captureCurrentLayout(sidebarWidth: nil, notesListWidth: nil) else { return }
        onLayoutChange?(layout)
    }

    private func framesApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 1
            && abs(lhs.origin.y - rhs.origin.y) < 1
            && abs(lhs.size.width - rhs.size.width) < 1
            && abs(lhs.size.height - rhs.size.height) < 1
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

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowReady: onWindowReady)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(to: nsView.window)
        }
    }

    final class Coordinator {
        let onWindowReady: (NSWindow) -> Void
        private weak var attachedWindow: NSWindow?

        init(onWindowReady: @escaping (NSWindow) -> Void) {
            self.onWindowReady = onWindowReady
        }

        func attachIfNeeded(to window: NSWindow?) {
            guard let window, attachedWindow !== window else { return }
            attachedWindow = window
            onWindowReady(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WindowLayoutController.shared.reapplyWindowChrome()
            }
        }
    }
}
