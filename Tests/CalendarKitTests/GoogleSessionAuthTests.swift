@testable import CalendarKit
import XCTest

final class GoogleSessionAuthTests: XCTestCase {
    func testBuildsSAPISIDHashHeader() {
        let cookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "test-sapisid-value",
            .domain: ".google.com",
            .path: "/",
        ])!

        let header = GoogleSessionAuth.sapisidHash(cookies: [cookie])
        XCTAssertNotNil(header)
        XCTAssertTrue(header?.hasPrefix("SAPISIDHASH ") == true)
        XCTAssertTrue(header?.contains("_") == true)
    }

    func testPrefersSecurePAPISIDWhenSAPISIDMissing() {
        let cookie = HTTPCookie(properties: [
            .name: "__Secure-1PAPISID",
            .value: "secure-value",
            .domain: ".google.com",
            .path: "/",
        ])!

        XCTAssertEqual(GoogleSessionAuth.sapisidCookieValue(from: [cookie]), "secure-value")
    }
}
