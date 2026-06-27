import AppKit
import ApplicationServices
import Carbon.HIToolbox
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
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandlerRef: EventHandlerRef?
    private var previousFrontmostApp: NSRunningApplication?
    private var lastHotkeyHandledAt: TimeInterval = 0

    private static let carbonHotKeySignature: UInt32 = 0x4E756350 // 'NucP'
    private static let carbonHotKeyID: UInt32 = 1

    private override init() {
        super.init()
    }

    func start() {
        installLocalKeyMonitorIfNeeded()
        registerCarbonHotKeyIfNeeded()

        if eventTap == nil {
            _ = startEventTap()
        }

        installGlobalKeyMonitorIfNeeded()

        if eventTap == nil, !AXIsProcessTrusted() {
            promptForAccessibilityIfNeeded()
        }
    }

    func refreshEventTapIfNeeded() {
        installLocalKeyMonitorIfNeeded()
        registerCarbonHotKeyIfNeeded()
        stopEventTap()
        _ = startEventTap()
        installGlobalKeyMonitorIfNeeded()
    }

    func stop() {
        unregisterCarbonHotKey()
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

        guard let viewModel = AppViewModel.current else {
            NSLog("Nucleus: clipboard picker unavailable — AppViewModel not ready")
            return
        }

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

    private func installLocalKeyMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.matchesHotkey(event) else { return event }
            self.handleHotkey()
            return nil
        }
    }

    private func installGlobalKeyMonitorIfNeeded() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.matchesHotkey(event) else { return }
            Task { @MainActor in
                self.handleHotkey()
            }
        }
    }

    private func handleHotkey() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHotkeyHandledAt > 0.25 else { return }
        lastHotkeyHandledAt = now
        presentPicker()
    }

    private func registerCarbonHotKeyIfNeeded() {
        guard carbonHotKeyRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonHotKeyHandler,
            1,
            &eventSpec,
            userInfo,
            &carbonEventHandlerRef
        )
        guard installStatus == noErr else {
            NSLog("Nucleus: failed to install clipboard hotkey handler (%d)", installStatus)
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(Self.carbonHotKeySignature),
            id: Self.carbonHotKeyID
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
        guard registerStatus == noErr else {
            NSLog("Nucleus: failed to register clipboard hotkey (%d)", registerStatus)
            unregisterCarbonHotKey()
            return
        }
    }

    private func unregisterCarbonHotKey() {
        if let carbonHotKeyRef {
            UnregisterEventHotKey(carbonHotKeyRef)
            self.carbonHotKeyRef = nil
        }
        if let carbonEventHandlerRef {
            RemoveEventHandler(carbonEventHandlerRef)
            self.carbonEventHandlerRef = nil
        }
    }

    private static let carbonHotKeyHandler: EventHandlerUPP = { _, event, userInfo -> OSStatus in
        guard let event, let userInfo else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        guard hotKeyID.signature == OSType(carbonHotKeySignature), hotKeyID.id == carbonHotKeyID else {
            return noErr
        }

        let controller = Unmanaged<ClipboardPasteController>.fromOpaque(userInfo).takeUnretainedValue()
        DispatchQueue.main.async {
            Task { @MainActor in
                controller.handleHotkey()
            }
        }
        return noErr
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
            tap: Self.hidEventTapLocation,
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

    private static let hidEventTapLocation = CGEventTapLocation(rawValue: 0)! // kCGHIDEventTap

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let userInfo {
                let controller = Unmanaged<ClipboardPasteController>.fromOpaque(userInfo).takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.refreshEventTapIfNeeded()
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
                controller.handleHotkey()
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
        guard hotkeyModifiersMatch(event.modifierFlags) else { return false }
        return event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    private static func matchesCGEvent(_ event: CGEvent) -> Bool {
        guard hotkeyModifiersMatch(event.flags) else { return false }

        if event.getIntegerValueField(.keyboardEventKeycode) == 9 {
            return true
        }

        return eventUnicodeCharacter(event)?.lowercased() == "v"
    }

    private static func hotkeyModifiersMatch(_ flags: NSEvent.ModifierFlags) -> Bool {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), mods.contains(.shift) else { return false }
        return !mods.contains(.option) && !mods.contains(.control)
    }

    private static func hotkeyModifiersMatch(_ flags: CGEventFlags) -> Bool {
        let mods = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard mods.contains(.maskCommand), mods.contains(.maskShift) else { return false }
        return !mods.contains(.maskAlternate) && !mods.contains(.maskControl)
    }

    private static func eventUnicodeCharacter(_ event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

extension ClipboardPasteController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        dismissPicker(reactivatePreviousApp: true)
    }
}
