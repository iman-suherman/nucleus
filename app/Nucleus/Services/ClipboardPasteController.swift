import AppKit
import ApplicationServices
import ClipboardKit
import NucleusKit
import SwiftUI

@MainActor
final class ClipboardPasteController: NSObject {
    static let shared = ClipboardPasteController()

    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var previousFrontmostApp: NSRunningApplication?

    private override init() {
        super.init()
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.matchesHotkey(event) else { return event }
            self.presentPicker()
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.matchesHotkey(event) else { return }
            Task { @MainActor in
                guard !NSApp.isActive else { return }
                self.presentPicker()
            }
        }
    }

    func stop() {
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
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        guard let viewModel = AppViewModel.current else { return }

        requestAccessibilityIfNeeded()

        previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        viewModel.clipboardSearchQuery = ""

        let pickerView = ClipboardPickerView(
            entries: viewModel.filteredClipboardEntries(),
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
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Paste from Clipboard History"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    private func apply(_ entry: ClipboardEntry) {
        let targetApp = previousFrontmostApp ?? NSWorkspace.shared.frontmostApplication
        dismissPicker(reactivatePreviousApp: false)

        ClipboardMonitorService.shared.preparePaste(entry.content)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.content, forType: .string)
        ClipboardMonitorService.shared.completePaste()

        targetApp?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.simulateCommandV()
        }
    }

    private func dismissPicker(reactivatePreviousApp: Bool) {
        panel?.orderOut(nil)
        panel = nil

        if reactivatePreviousApp, let previousFrontmostApp, previousFrontmostApp != NSRunningApplication.current {
            previousFrontmostApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        previousFrontmostApp = nil
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static func matchesHotkey(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift]
            && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    private static func simulateCommandV() {
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(9) // ANSI V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}

extension ClipboardPasteController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        dismissPicker(reactivatePreviousApp: true)
    }
}
