import AppKit
import SwiftUI

enum MarketingScreenshotCapture {
    private static let targetContentSize = NSSize(width: 1280, height: 840)
    private static var didSchedule = false

    static func scheduleIfNeeded() {
        guard MarketingScreenshotMode.isActive,
              MarketingScreenshotMode.exportPath != nil,
              !didSchedule else { return }
        didSchedule = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            captureAndExit()
        }
    }

    static func applyMarketingFrame(to window: NSWindow) {
        window.styleMask.remove(.fullSizeContentView)
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
        window.setFrame(frame, display: true)
        window.center()
    }

    private static func captureAndExit() {
        guard let exportPath = MarketingScreenshotMode.exportPath,
              let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }) else {
            NSApp.terminate(nil)
            return
        }

        applyMarketingFrame(to: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let contentView = window.contentView else {
            NSApp.terminate(nil)
            return
        }

        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            NSApp.terminate(nil)
            return
        }

        contentView.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            NSApp.terminate(nil)
            return
        }

        let url = URL(fileURLWithPath: exportPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? png.write(to: url)
        NSApp.terminate(nil)
    }
}

struct MarketingScreenshotWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard MarketingScreenshotMode.isActive,
                  let window = view.window ?? NSApp.windows.first else { return }
            MarketingScreenshotCapture.applyMarketingFrame(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
