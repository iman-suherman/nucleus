import AppKit
import WebKit

/// Hosts a shared `WKWebView` with AppKit-level clipping so web content cannot paint over the toolbar.
final class EmbeddedWebViewContainer: NSView {
    private(set) weak var embeddedWebView: WKWebView?
    private var edgeConstraints: [NSLayoutConstraint] = []

    override var isFlipped: Bool { true }

    /// Prevent loaded web pages (especially Gmail) from expanding the SwiftUI layout beyond the detail pane.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func embed(_ webView: WKWebView) {
        if webView.superview !== self {
            webView.removeFromSuperview()
            addSubview(webView)
        }
        embeddedWebView = webView
        wantsLayer = true
        layer?.masksToBounds = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.deactivate(edgeConstraints)
        edgeConstraints = [
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        NSLayoutConstraint.activate(edgeConstraints)
    }

    func setEmbeddedVisibility(_ visible: Bool) {
        isHidden = !visible
        alphaValue = visible ? 1 : 0
        embeddedWebView?.setEmbeddedVisibility(visible)
    }
}
