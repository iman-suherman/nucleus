@testable import CalendarKit
import XCTest

final class MeetingLinkExtractorTests: XCTestCase {
    func testPrefersConferenceURL() {
        let link = MeetingLinkExtractor.extract(
            conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            url: URL(string: "https://example.com"),
            description: "fallback",
            location: "Room 1"
        )
        XCTAssertEqual(link, "https://meet.google.com/abc-defg-hij")
    }

    func testExtractsGoogleMeetFromDescription() {
        let link = MeetingLinkExtractor.extract(
            description: "Join at https://meet.google.com/team-sync-123",
            location: "Online"
        )
        XCTAssertEqual(link, "https://meet.google.com/team-sync-123")
    }

    func testUsesLocationWhenHTTP() {
        let link = MeetingLinkExtractor.extract(
            description: "",
            location: "https://teams.microsoft.com/l/meetup-join/19%3ameeting"
        )
        XCTAssertEqual(link, "https://teams.microsoft.com/l/meetup-join/19%3ameeting")
    }
}
