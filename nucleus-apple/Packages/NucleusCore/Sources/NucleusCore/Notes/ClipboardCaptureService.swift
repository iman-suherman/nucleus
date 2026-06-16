import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Phase 3: Manual clipboard capture (macOS automatic history stays macOS-only).
@MainActor
public enum ClipboardCaptureService {
    public static func currentText() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    public static func hasContent() -> Bool {
        guard let text = currentText() else { return false }
        return !text.isEmpty
    }
}
