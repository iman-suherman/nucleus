import XCTest
import NucleusKit
@testable import MailKit

final class MailMessageParserTests: XCTestCase {
    func testParsesMetadataPayload() {
        let payload: [String: Any] = [
            "id": "msg-1",
            "threadId": "thread-1",
            "snippet": "Hello there",
            "labelIds": ["INBOX", "UNREAD"],
            "internalDate": "1718448000000",
            "payload": [
                "headers": [
                    ["name": "From", "value": "Michael Espana <michael@example.com>"],
                    ["name": "Subject", "value": "Production deployment approval"],
                ],
            ],
        ]

        let accountID = UUID()
        let summary = MailMessageParser.parse(payload, accountID: accountID)
        XCTAssertEqual(summary?.subject, "Production deployment approval")
        XCTAssertEqual(summary?.fromName, "Michael Espana")
        XCTAssertTrue(summary?.isUnread ?? false)
    }
}
