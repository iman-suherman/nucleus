import AppKit
import ClipboardKit
import NucleusKit
import SwiftUI

@MainActor
final class ClipboardPasteController: NSObject {
    static let shared = ClipboardPasteController()

    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var outsideClickMonitor: Any?
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
        ClipboardPasteReuseStore.record(entry: entry)
        dismissPicker(reactivatePreviousApp: false)

        ClipboardMonitorService.shared.preparePaste(entry.content)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.content, forType: .string)
        ClipboardMonitorService.shared.completePaste()

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
}

extension ClipboardPasteController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        dismissPicker(reactivatePreviousApp: true)
    }
}
