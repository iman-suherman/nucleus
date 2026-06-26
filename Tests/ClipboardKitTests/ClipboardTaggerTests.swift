import XCTest
import NucleusKit
@testable import ClipboardKit

final class ClipboardTaggerTests: XCTestCase {
    func testInfersDockerTag() {
        let tags = ClipboardTagger.inferTags(from: "docker compose up")
        XCTAssertTrue(tags.contains("docker"))
    }

    func testSearchRanksPinnedHigher() {
        let entries = [
            ClipboardEntry(content: "kubectl get pods", isPinned: false),
            ClipboardEntry(content: "kubectl logs deploy", isPinned: true),
        ]
        let ranked = ClipboardSearch.rank(entries, query: "kubectl")
        XCTAssertEqual(ranked.first?.isPinned, true)
    }

    func testSearchMatchesAllTokens() {
        let entries = [
            ClipboardEntry(content: "docker compose up postgres", sourceApplication: "Terminal"),
            ClipboardEntry(content: "kubectl get pods", sourceApplication: "Terminal"),
        ]
        let ranked = ClipboardSearch.rank(entries, query: "docker postgres")
        XCTAssertEqual(ranked.first?.content, "docker compose up postgres")
    }
}
