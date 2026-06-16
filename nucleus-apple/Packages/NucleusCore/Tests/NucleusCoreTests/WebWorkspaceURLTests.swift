import XCTest
@testable import NucleusCore

final class WebWorkspaceURLTests: XCTestCase {
    func testMailInboxURLContainsEmail() {
        let url = WebWorkspaceURLs.mailInbox(for: "user@gmail.com")
        XCTAssertEqual(url?.absoluteString, "https://mail.google.com/mail/u/?authuser=user@gmail.com")
    }

    func testExternalLinkPolicyForMeet() {
        let url = URL(string: "https://meet.google.com/abc-defg-hij")!
        XCTAssertTrue(ExternalLinkPolicy.shouldOpenExternally(url: url))
    }
}
