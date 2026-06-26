import AppKit
import ApplicationServices
import ClipboardKit
import NucleusKit
import SwiftUI

@MainActor
final class ClipboardPasteController: NSObject {
    static let shared = ClipboardPasteController()

    private var panel: NSPanel?
    private var feedbackPanel: NSPanel?
    private var feedbackDismissTask: Task<Void, Never>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var outsideClickMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var previousFrontmostApp: NSRunningApplication?

    private override init() {
        super.init()
    }

    func start() {
        if eventTap != nil || globalMonitor != nil || localMonitor != nil {
            refreshEventTapIfNeeded()
            return
        }

        if startEventTap() {
            return
        }

        installFallbackKeyMonitors()
    }

    func refreshEventTapIfNeeded() {
        guard eventTap == nil, AXIsProcessTrusted(), startEventTap() else { return }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    func stop() {
        stopEventTap()

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        dismissPicker(reactivatePreviousApp: false)
    }

    func presentPicker() {
        if panel != nil {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        guard let viewModel = AppViewModel.current else { return }

        previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        if previousFrontmostApp?.bundleIdentifier == Bundle.main.bundleIdentifier {
            previousFrontmostApp = nil
        }
        viewModel.clipboardSearchQuery = ""

        let entries = viewModel.clipboardEntries
        Task {
            await ClipboardSearchEngine.shared.rebuild(from: entries)
        }

        let pickerView = ClipboardPickerView(
            entries: entries,
            onSelect: { [weak self] entry in
                self?.apply(entry)
            },
            onDismiss: { [weak self] in
                self?.dismissPicker(reactivatePreviousApp: true)
            }
        )

        let hosting = NSHostingController(rootView: pickerView)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 520, height: 360)

        let panel = NSPanel(
            contentRect: hosting.view.bounds,
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Paste from Clipboard History"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        installOutsideClickMonitor()
    }

    private func apply(_ entry: ClipboardEntry) {
        let targetApp = previousFrontmostApp ?? NSWorkspace.shared.frontmostApplication
        let copiedContent = entry.content
        ClipboardPasteReuseStore.record(entry: entry)
        dismissPicker(reactivatePreviousApp: false)

        ClipboardMonitorService.shared.preparePaste(copiedContent)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copiedContent, forType: .string)
        ClipboardMonitorService.shared.completePaste()

        showPasteFeedback(content: copiedContent)
        targetApp?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }

    private func dismissPicker(reactivatePreviousApp: Bool) {
        removeOutsideClickMonitor()
        panel?.orderOut(nil)
        panel = nil

        if reactivatePreviousApp, let previousFrontmostApp, previousFrontmostApp != NSRunningApplication.current {
            previousFrontmostApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        previousFrontmostApp = nil
    }

    private func showPasteFeedback(content: String) {
        feedbackDismissTask?.cancel()
        dismissPasteFeedback()

        let hosting = NSHostingController(rootView: ClipboardPasteFeedbackView(content: content))
        hosting.view.layoutSubtreeIfNeeded()
        let fittingSize = hosting.view.fittingSize
        let panelSize = NSSize(
            width: max(280, min(fittingSize.width, 520)),
            height: max(72, fittingSize.height)
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.setFrame(panelFrame(for: panelSize), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        feedbackPanel = panel
        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            dismissPasteFeedback()
        }
    }

    private func dismissPasteFeedback() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil

        guard let feedbackPanel else { return }
        let panel = feedbackPanel
        self.feedbackPanel = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func panelFrame(for size: NSSize) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = NSPoint(
            x: visible.midX - (size.width / 2),
            y: visible.midY - (size.height / 2)
        )
        return NSRect(origin: origin, size: size)
    }

    private func installFallbackKeyMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.matchesHotkey(event) else { return event }
            self.presentPicker()
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.matchesHotkey(event) else { return }
            Task { @MainActor in
                self.presentPicker()
            }
        }
    }

    @discardableResult
    private func startEventTap() -> Bool {
        guard AXIsProcessTrusted() else {
            promptForAccessibilityIfNeeded()
            return false
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func stopEventTap() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }

    private func promptForAccessibilityIfNeeded() {
        let key = "nucleus.clipboardPaste.accessibilityPromptShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let userInfo {
                let controller = Unmanaged<ClipboardPasteController>.fromOpaque(userInfo).takeUnretainedValue()
                DispatchQueue.main.async {
                    if let tap = controller.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        guard matchesCGEvent(event) else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<ClipboardPasteController>.fromOpaque(userInfo).takeUnretainedValue()
        DispatchQueue.main.async {
            Task { @MainActor in
                controller.presentPicker()
            }
        }
        return nil
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.dismissPicker(reactivatePreviousApp: true)
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private static func matchesHotkey(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift]
            && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    private static func matchesCGEvent(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == 9 else { return false }

        let flags = event.flags
        return flags.contains(.maskCommand)
            && flags.contains(.maskShift)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskControl)
    }
}

extension ClipboardPasteController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        dismissPicker(reactivatePreviousApp: true)
    }
}
