import AppKit
import WebKit

/// Hosts a shared `WKWebView` with AppKit-level clipping so web content cannot paint over the toolbar.
final class EmbeddedWebViewContainer: NSView {
    private(set) weak var embeddedWebView: WKWebView?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        embeddedWebView?.frame = bounds
    }

    func embed(_ webView: WKWebView) {
        if webView.superview !== self {
            webView.removeFromSuperview()
            addSubview(webView)
        }
        embeddedWebView = webView
        wantsLayer = true
        layer?.masksToBounds = true
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
    }

    func setEmbeddedVisibility(_ visible: Bool) {
        isHidden = !visible
        alphaValue = visible ? 1 : 0
        embeddedWebView?.setEmbeddedVisibility(visible)
    }
}
