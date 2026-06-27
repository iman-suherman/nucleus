import AppKit
import Foundation
import NucleusKit
import SwiftUI

enum WindowLayoutMetrics {
    static let minWidth: CGFloat = 920
    static let minHeight: CGFloat = 680
    static let defaultWidth: CGFloat = 1320
    static let defaultHeight: CGFloat = 880
}

private extension NSScreen {
    var layoutDisplayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
final class WindowLayoutController {
    static let shared = WindowLayoutController()

    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private weak var trackedWindow: NSWindow?
    private var onLayoutChange: ((WindowLayoutState) -> Void)?
    private var hasRestoredInitialFrame = false
    private var isApplyingProgrammatically = false
    private var deferredScreenRestoreTask: DispatchWorkItem?

    private init() {}

    func startTracking(onChange: @escaping (WindowLayoutState) -> Void) {
        onLayoutChange = onChange
    }

    func attach(to window: NSWindow?) {
        guard let window else { return }
        guard trackedWindow !== window else { return }

        detachObservers()
        trackedWindow = window
        hasRestoredInitialFrame = false
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
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.publishCurrentLayout()
        }
        restoreSavedFrameOnce(from: AppSettings.shared.windowLayout)
        scheduleDeferredScreenRestore(from: AppSettings.shared.windowLayout)
    }

    /// Restores saved frame once per window attachment. Frame is not re-applied after user interaction.
    func restoreSavedFrameOnce(from layout: WindowLayoutState?) {
        guard !hasRestoredInitialFrame else { return }
        guard let window = trackedWindow else { return }
        hasRestoredInitialFrame = true

        var target = window.frame
        if let layout, layout.width > 0, layout.height > 0 {
            target.size = NSSize(
                width: max(layout.width, WindowLayoutMetrics.minWidth),
                height: max(layout.height, WindowLayoutMetrics.minHeight)
            )
        }

        let hasSavedOrigin = layout?.originX != nil && layout?.originY != nil
        if hasSavedOrigin, let originX = layout?.originX, let originY = layout?.originY {
            target.origin = NSPoint(x: originX, y: originY)
        }

        let targetScreen = screenForSavedLayout(layout) ?? window.screen ?? NSScreen.main ?? NSScreen.screens.first
        let constrained = frameConstrainedToVisibleScreen(
            target,
            on: targetScreen,
            centerIfNeeded: layout == nil || !hasSavedOrigin
        )
        guard !framesApproximatelyEqual(window.frame, constrained) else { return }

        isApplyingProgrammatically = true
        window.setFrame(constrained, display: true)
        isApplyingProgrammatically = false
        configureWindowChrome(window)
    }

    /// External displays can appear slightly after launch; re-apply saved frame once the target screen is available.
    private func scheduleDeferredScreenRestore(from layout: WindowLayoutState?) {
        deferredScreenRestoreTask?.cancel()
        guard layout?.displayID != nil || layout?.screenOriginX != nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, let window = self.trackedWindow, let layout else { return }
            guard let targetScreen = self.screenForSavedLayout(layout) else { return }
            if window.screen?.layoutDisplayID == targetScreen.layoutDisplayID { return }

            var target = window.frame
            if layout.width > 0, layout.height > 0 {
                target.size = NSSize(
                    width: max(layout.width, WindowLayoutMetrics.minWidth),
                    height: max(layout.height, WindowLayoutMetrics.minHeight)
                )
            }
            if let originX = layout.originX, let originY = layout.originY {
                target.origin = NSPoint(x: originX, y: originY)
            }

            let constrained = self.frameConstrainedToVisibleScreen(
                target,
                on: targetScreen,
                centerIfNeeded: false
            )
            guard !self.framesApproximatelyEqual(window.frame, constrained) else { return }

            self.isApplyingProgrammatically = true
            window.setFrame(constrained, display: true)
            self.isApplyingProgrammatically = false
            self.configureWindowChrome(window)
        }
        deferredScreenRestoreTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func persistLayoutNow() {
        guard !isApplyingProgrammatically else { return }
        guard let layout = captureCurrentLayout(sidebarWidth: nil, notesListWidth: nil) else { return }

        var merged = AppSettings.shared.windowLayout ?? layout
        merged.width = layout.width
        merged.height = layout.height
        merged.originX = layout.originX
        merged.originY = layout.originY
        merged.screenOriginX = layout.screenOriginX
        merged.screenOriginY = layout.screenOriginY
        merged.screenWidth = layout.screenWidth
        merged.screenHeight = layout.screenHeight
        merged.displayID = layout.displayID
        AppSettings.shared.windowLayout = merged
        onLayoutChange?(layout)
    }

    private func configureWindowChrome(_ window: NSWindow) {
        window.title = "Nucleus"
        window.titleVisibility = .hidden
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
    }

    private func screenForSavedLayout(_ layout: WindowLayoutState?) -> NSScreen? {
        guard let layout else { return nil }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let displayID = layout.displayID {
            for screen in screens where screen.layoutDisplayID == displayID {
                return screen
            }
        }

        if let screenOriginX = layout.screenOriginX,
           let screenOriginY = layout.screenOriginY,
           let screenWidth = layout.screenWidth,
           let screenHeight = layout.screenHeight {
            let savedFrame = NSRect(
                x: screenOriginX,
                y: screenOriginY,
                width: screenWidth,
                height: screenHeight
            )
            for screen in screens where screenFramesApproximatelyEqual(screen.frame, savedFrame) {
                return screen
            }
        }

        if let originX = layout.originX, let originY = layout.originY {
            let windowCenter = NSPoint(
                x: originX + layout.width / 2,
                y: originY + layout.height / 2
            )
            for screen in screens where screen.frame.contains(windowCenter) {
                return screen
            }
        }

        return nil
    }

    private func frameConstrainedToVisibleScreen(
        _ frame: NSRect,
        on screen: NSScreen?,
        centerIfNeeded: Bool
    ) -> NSRect {
        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return frame }

        var result = frame
        result.size.width = min(max(result.size.width, WindowLayoutMetrics.minWidth), visible.width)
        result.size.height = min(max(result.size.height, WindowLayoutMetrics.minHeight), visible.height)

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
        let screenFrame = window.screen?.frame
        return WindowLayoutState(
            width: Double(frame.size.width),
            height: Double(frame.size.height),
            originX: Double(frame.origin.x),
            originY: Double(frame.origin.y),
            screenOriginX: screenFrame.map { Double($0.origin.x) },
            screenOriginY: screenFrame.map { Double($0.origin.y) },
            screenWidth: screenFrame.map { Double($0.size.width) },
            screenHeight: screenFrame.map { Double($0.size.height) },
            displayID: window.screen?.layoutDisplayID,
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

    private func screenFramesApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 4
            && abs(lhs.origin.y - rhs.origin.y) < 4
            && abs(lhs.size.width - rhs.size.width) < 4
            && abs(lhs.size.height - rhs.size.height) < 4
    }

    private func detachObservers() {
        deferredScreenRestoreTask?.cancel()
        deferredScreenRestoreTask = nil
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }
}

private final class WindowAttachmentView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

struct WindowLayoutAccessor: NSViewRepresentable {
    let onWindowReady: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowReady: onWindowReady)
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView()
        view.onWindowChange = { window in
            guard let window else { return }
            context.coordinator.attachIfNeeded(to: window)
        }
        if let window = view.window {
            context.coordinator.attachIfNeeded(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowAttachmentView else { return }
        view.onWindowChange = { window in
            guard let window else { return }
            context.coordinator.attachIfNeeded(to: window)
        }
        if let window = view.window {
            context.coordinator.attachIfNeeded(to: window)
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
        }
    }
}
