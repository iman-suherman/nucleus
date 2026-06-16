import XCTest
@testable import ClipboardKit

final class ClipboardPasswordAnalyzerTests: XCTestCase {
    func testDetectsStrongPassword() {
        let analysis = ClipboardPasswordAnalyzer.analyze("Tr0ub4dor&3")
        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis?.extractedPassword, "Tr0ub4dor&3")
        XCTAssertEqual(analysis?.confidence, .high)
    }

    func testDetectsLabeledPassword() {
        let analysis = ClipboardPasswordAnalyzer.analyze("password: MyS3cret!")
        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis?.extractedPassword, "MyS3cret!")
        XCTAssertEqual(analysis?.confidence, .high)
    }

    func testIgnoresPlainSentence() {
        let analysis = ClipboardPasswordAnalyzer.analyze(
            "Please remember to update the staging credentials tomorrow morning"
        )
        XCTAssertNil(analysis)
    }

    func testIgnoresURL() {
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze("https://example.com/login"))
    }

    func testIgnoresShortValues() {
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze("abc123"))
    }
}
