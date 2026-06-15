import WebKit

extension WKWebView {
    func setEmbeddedVisibility(_ visible: Bool) {
        isHidden = !visible
        alphaValue = visible ? 1 : 0
    }
}
