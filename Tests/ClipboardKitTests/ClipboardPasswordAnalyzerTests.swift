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

    func testIgnoresCommonWordsWithPunctuation() {
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze("HelloWorld!"))
    }

    func testIgnoresCodeIdentifiers() {
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze("userConfig_v2"))
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze("myVariableName"))
    }

    func testIgnoresPassInProse() {
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze("Please pass the salt to the server"))
    }

    func testIgnoresPlaceholderLabeledSecret() {
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze("password: changeme"))
    }

    func testIgnoresMultiLineDocument() {
        let content = """
        Here are the deployment notes for staging.
        Remember to rotate credentials after the migration completes.
        The dashboard should show green once sync finishes.
        """
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze(content))
    }

    func testDetectsLabeledPasswordInMultiLineDocument() {
        let content = """
        Staging credentials
        password: Z9k!mP2xQ7vL
        """
        let analysis = ClipboardPasswordAnalyzer.analyze(content)
        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis?.extractedPassword, "Z9k!mP2xQ7vL")
    }

    func testIgnoresGitCommitHash() {
        XCTAssertNil(ClipboardPasswordAnalyzer.analyze("a1b2c3d4e5f6789012345678901234567890abcd"))
    }
}
