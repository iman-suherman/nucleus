import AppKit
import Combine
import Foundation
import ClipboardKit

@MainActor
final class ClipboardMonitorService: ObservableObject {
    static let shared = ClipboardMonitorService()

    @Published private(set) var lastChangeCount: Int = NSPasteboard.general.changeCount

    private var timer: Timer?
    private var lastCapturedContent: String?
    private var isApplyingPaste = false

    var onCapture: ((ClipboardCapture) -> Void)?

    private init() {}

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        guard !isApplyingPaste else { return }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let content = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty,
              content != lastCapturedContent else {
            return
        }

        lastCapturedContent = content
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        onCapture?(ClipboardCapture(content: content, sourceApplication: source))
    }

    func preparePaste(_ content: String) {
        isApplyingPaste = true
        lastCapturedContent = content
    }

    func completePaste() {
        lastChangeCount = NSPasteboard.general.changeCount
        isApplyingPaste = false
    }
}
