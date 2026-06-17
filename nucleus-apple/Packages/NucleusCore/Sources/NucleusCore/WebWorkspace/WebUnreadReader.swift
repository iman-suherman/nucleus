import Foundation
import WebKit

/// Foreground unread counts from loaded Gmail / Chat web sessions (no background polling on iOS).
@MainActor
public enum WebUnreadReader {
    public static let mailScript = """
    (function() {
      const titleMatch = document.title.match(/\\((\\d+)\\)/);
      if (titleMatch) return parseInt(titleMatch[1], 10);

      const selectors = [
        'a[href*="#inbox"]',
        'a[href*="inbox"]',
        '[data-tooltip*="Inbox"]',
        '[aria-label*="Inbox"]',
        '[aria-label*="inbox"]'
      ];

      for (const selector of selectors) {
        for (const link of document.querySelectorAll(selector)) {
          const label = link.getAttribute('aria-label')
            || link.getAttribute('data-tooltip')
            || link.getAttribute('title')
            || '';
          let match = label.match(/(\\d+)\\s+unread/i);
          if (match) return parseInt(match[1], 10);
          match = label.match(/inbox[,\\s]+(\\d+)/i);
          if (match) return parseInt(match[1], 10);
          match = label.match(/inbox[^\\d]*(\\d+)/i);
          if (match) return parseInt(match[1], 10);

          for (const badge of link.querySelectorAll('span, div')) {
            const text = (badge.textContent || '').trim();
            if (/^\\d+$/.test(text)) return parseInt(text, 10);
          }
        }
      }
      return 0;
    })();
    """

    public static let chatScript = """
    (function() {
      const titleMatch = document.title.match(/\\((\\d+)\\)/);
      if (titleMatch) return parseInt(titleMatch[1], 10);

      const selectors = [
        '[aria-label*="unread"]',
        '[data-tooltip*="unread"]',
        '[aria-label*="Unread"]'
      ];

      for (const selector of selectors) {
        for (const node of document.querySelectorAll(selector)) {
          const label = node.getAttribute('aria-label')
            || node.getAttribute('data-tooltip')
            || '';
          const match = label.match(/(\\d+)/);
          if (match) return parseInt(match[1], 10);
        }
      }
      return 0;
    })();
    """

    public static func pollUnread(
        accountID: UUID,
        surface: WebSurface,
        onCount: @escaping (Int) -> Void
    ) {
        guard let webView = WebViewRegistry.existingWebView(accountID: accountID, surface: surface),
              WebWorkspaceURLs.isLoadedContent(webView.url, for: surface) else {
            onCount(0)
            return
        }

        let script = surface == .mail ? mailScript : chatScript
        webView.evaluateJavaScript(script) { result, _ in
            let count: Int
            if let value = result as? Int {
                count = value
            } else if let value = result as? NSNumber {
                count = value.intValue
            } else {
                count = 0
            }
            onCount(count)
        }
    }
}
