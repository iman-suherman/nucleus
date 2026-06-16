#if canImport(AppKit)
import AppKit
import Combine
import Foundation

@MainActor
public final class ClipboardMonitorService: ObservableObject {
    public static let shared = ClipboardMonitorService()

    @Published public private(set) var lastChangeCount: Int = NSPasteboard.general.changeCount

    private var timer: Timer?
    private var lastCapturedContent: String?
    private var isApplyingPaste = false

    public var onCapture: ((ClipboardCapture) -> Void)?
    public var isCaptureEnabled: () -> Bool = { true }

    private init() {}

    public func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        guard isCaptureEnabled() else { return }
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

    public func preparePaste(_ content: String) {
        isApplyingPaste = true
        lastCapturedContent = content
    }

    public func completePaste() {
        lastChangeCount = NSPasteboard.general.changeCount
        isApplyingPaste = false
    }

    public static func copyToPasteboard(_ content: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }
}
#endif
