import XCTest
@testable import NucleusKit

final class ExternalLinkPolicyTests: XCTestCase {
    func testExternalHostsOpenInBrowser() {
        let url = URL(string: "https://docs.google.com/document/d/abc")!
        XCTAssertTrue(ExternalLinkPolicy.shouldOpenExternally(url: url))
    }

    func testGmailStaysInWebView() {
        let url = URL(string: "https://mail.google.com/mail/u/0/")!
        XCTAssertFalse(ExternalLinkPolicy.shouldOpenExternally(url: url))
    }
}
